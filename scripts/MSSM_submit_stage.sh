#!/bin/bash

# Submit one ColumnFlow pipeline stage at a time, optionally splitting
# data, backgrounds, ggphi and bbphi into independent submissions.
#
# Usage:
#   ./MSSM_submit_stage.sh <stage> <config-option> <sample-group> [extra law options]
#
# Datacard-plot usage:
#   ./MSSM_submit_stage.sh plot1d <config-option> datacard <bdt-variable> [extra law options]
#   ./MSSM_submit_stage.sh plot1d-shifted <config-option> datacard <bdt-variable> [extra law options]
#
# Examples:
#   ./MSSM_submit_stage.sh calibrate 22and23_emu data
#   ./MSSM_submit_stage.sh calibrate 22and23_emu backgrounds
#   ./MSSM_submit_stage.sh calibrate 22and23_emu ggphi
#   ./MSSM_submit_stage.sh calibrate 22and23_emu bbphi
#
#   # Exact final distributions entering the datacards at M100:
#   ./MSSM_submit_stage.sh plot1d 22and23_emu datacard bdt_D_sig_vs_Disc_ggphi_M100
#   ./MSSM_submit_stage.sh plot1d 22and23_emu datacard bdt_D_sig_vs_Disc_bbphi_M100
#   ./MSSM_submit_stage.sh plot1d 22and23_emu datacard bdt_D_DY_M100
#   ./MSSM_submit_stage.sh plot1d 22and23_emu datacard bdt_D_TT_M100
#
#   # Same distributions with nominal/up/down systematic variations:
#   ./MSSM_submit_stage.sh plot1d-shifted 22and23_emu datacard bdt_D_DY_M100
#
# sample-group:
#   data | backgrounds | DY | tt | singlet | other_bkgs |
#   signal | ggphi | bbphi | datacard
#
# stage:
#   calibrate | select | reduce | merge-reduced |
#   produce | create-hists | merge-hists | merge-shifted |
#   plot1d | plot1d-shifted

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Arguments
# =============================================================================

if (( $# < 3 )); then
    echo "Usage: $0 <stage> <config-option> <sample-group> [extra law options]"
    echo
    echo "Stages:"
    echo "  calibrate"
    echo "  select"
    echo "  reduce"
    echo "  merge-reduced"
    echo "  produce"
    echo "  create-hists"
    echo "  merge-hists"
    echo "  merge-shifted"
    echo "  plot1d"
    echo "  plot1d-shifted"
    echo
    echo "Sample groups:"
    echo "  data"
    echo "  backgrounds"
    echo "  DY"
    echo "  tt"
    echo "  singlet"
    echo "  other_bkgs"
    echo "  signal       (ggphi + bbphi)"
    echo "  ggphi"
    echo "  bbphi"
    echo "  datacard     (plot stages only; next argument must be one final BDT variable)"
    exit 1
fi

stage="$1"
config_option="$2"
sample_group="$3"
shift 3

# For the datacard plotting mode, the first argument after the sample group is
# the exact final variable used by one inference-model variant.
datacard_variable=""
if [[ "$sample_group" == "datacard" ]]; then
    case "$stage" in
        plot1d|plot1d-shifted)
            if (( $# < 1 )) || [[ "$1" == -* ]]; then
                echo "ERROR: sample group 'datacard' requires the final BDT variable." >&2
                echo "Example:" >&2
                echo "  $0 plot1d 22and23_emu datacard bdt_D_DY_M100" >&2
                exit 1
            fi
            datacard_variable="$1"
            shift
            ;;
        *)
            echo "ERROR: sample group 'datacard' is only valid for plot1d and plot1d-shifted." >&2
            exit 1
            ;;
    esac
fi

# Extra command line options supplied by the user are appended to the selected stage.
extra_args=("$@")

# =============================================================================
# ColumnFlow common setup
# =============================================================================

source "${SCRIPT_DIR}/common_run3_MSSM.sh"
set_common_vars "$config_option"

# =============================================================================
# Helpers
# =============================================================================

# Remove a trailing comma from the dataset/process CSV strings in common_run3_MSSM.sh.
strip_trailing_comma() {
    local value="$1"
    printf '%s' "${value%,}"
}

# Data is era dependent, so map every config to its matching data list.
data_for_config() {
    local cfg="$1"

    case "$cfg" in
        run3_2022_preEE_emu*)
            strip_trailing_comma "${data_egamma_2022preEE}${data_mu_2022preEE}"
            ;;
        run3_2022_postEE_emu*)
            strip_trailing_comma "${data_egamma_2022postEE}${data_mu_2022postEE}"
            ;;
        run3_2023_preBPix_emu*)
            strip_trailing_comma "${data_egamma_2023preBPix}${data_mu_2023preBPix}"
            ;;
        run3_2023_postBPix_emu*)
            strip_trailing_comma "${data_egamma_2023postBPix}${data_mu_2023postBPix}"
            ;;
        *)
            echo "ERROR: do not know which data datasets correspond to config '$cfg'" >&2
            return 1
            ;;
    esac
}

# Check whether an option was supplied explicitly in extra_args.
has_extra_option() {
    local option="$1"
    local arg

    for arg in "${extra_args[@]}"; do
        if [[ "$arg" == "$option" || "$arg" == "$option="* ]]; then
            return 0
        fi
    done

    return 1
}

# =============================================================================
# Datacard plotting specification
# =============================================================================

# These are set only for sample_group=datacard.
datacard_discriminant=""
datacard_mass=""
datacard_category=""
datacard_producers=""
datacard_signal_datasets=""
datacard_signal_processes=""
plot_processes="${processes:-}"

if [[ "$sample_group" == "datacard" ]]; then
    if [[ "$datacard_variable" =~ ^bdt_(D_sig_vs_Disc_ggphi|D_sig_vs_Disc_bbphi|D_DY|D_TT)_M([0-9]+)$ ]]; then
        datacard_discriminant="${BASH_REMATCH[1]}"
        datacard_mass="${BASH_REMATCH[2]}"
    else
        echo "ERROR: unsupported datacard variable '$datacard_variable'." >&2
        echo "Expected one of:" >&2
        echo "  bdt_D_sig_vs_Disc_ggphi_M<MASS>" >&2
        echo "  bdt_D_sig_vs_Disc_bbphi_M<MASS>" >&2
        echo "  bdt_D_DY_M<MASS>" >&2
        echo "  bdt_D_TT_M<MASS>" >&2
        exit 1
    fi

    # Determine the channel from the first config name.
    IFS=',' read -r -a config_array_tmp <<< "$config"
    first_cfg="${config_array_tmp[0]}"

    if [[ "$first_cfg" =~ _(emu|mutau|etau|tautau)($|_) ]]; then
        datacard_channel="${BASH_REMATCH[1]}"
    else
        echo "ERROR: cannot infer analysis channel from config '$first_cfg'." >&2
        exit 1
    fi

    # Match the canonical category definitions in MSSM_model.init_categories().
    case "$datacard_discriminant" in
        D_sig_vs_Disc_ggphi)
            datacard_category="cat_${datacard_channel}_sr__bdt_signal_M${datacard_mass}"
            datacard_signal_datasets="ggphi_phitt_${datacard_mass}"
            datacard_signal_processes="ggphi_phitt_${datacard_mass}"
            ;;

        D_sig_vs_Disc_bbphi)
            datacard_category="cat_${datacard_channel}_sr__bdt_signal_M${datacard_mass}"
            datacard_signal_datasets="bbphi_phitt_${datacard_mass}"
            datacard_signal_processes="bbphi_phitt_${datacard_mass}"
            ;;

        D_DY)
            datacard_category="cat_${datacard_channel}_sr__bdt_dy_M${datacard_mass}"
            datacard_signal_datasets="ggphi_phitt_${datacard_mass},bbphi_phitt_${datacard_mass}"
            datacard_signal_processes="ggphi_phitt_${datacard_mass},bbphi_phitt_${datacard_mass}"
            ;;

        D_TT)
            datacard_category="cat_${datacard_channel}_sr__bdt_tt_M${datacard_mass}"
            datacard_signal_datasets="ggphi_phitt_${datacard_mass},bbphi_phitt_${datacard_mass}"
            datacard_signal_processes="ggphi_phitt_${datacard_mass},bbphi_phitt_${datacard_mass}"
            ;;
    esac

    # Use the exact producer pair selected by the inference model:
    #   main_common + bdt_card_<mass-block>
    # The helper keeps this correct if BDT_MASS_BLOCK_SIZE changes.
    datacard_bdt_producer="$(
        python - "$datacard_mass" <<'PY'
import sys
from MSSM_H_tt.config.mass_points import get_bdt_card_producer_name
print(get_bdt_card_producer_name(int(sys.argv[1])))
PY
    )"

    datacard_producers="main_common,${datacard_bdt_producer}"

    # Exactly mirror the signal content of each derived inference-model variant.
    # processes_bkg already contains data + all standard backgrounds in the current
    # common_run3_MSSM.sh. Keep a fallback for older versions of that helper file.
    datacard_background_processes="${processes_bkg:-data,dy_lep,dy_tt_m50,h_ggf_htt_sm_prod_sm,st,tt,h_vbf_htt_sm,vh_htt,wj,vv,vvv}"
    plot_processes="${datacard_background_processes},${datacard_signal_processes}"
fi

# =============================================================================
# Dataset splitting
# =============================================================================

# Build the colon-separated dataset specification expected by multi-config tasks.
IFS=',' read -r -a config_array <<< "$config"

datasets_group=""

for cfg in "${config_array[@]}"; do
    case "$sample_group" in
        data)
            era_datasets="$(data_for_config "$cfg")"
            ;;

        backgrounds|background|bkg)
            era_datasets="$(strip_trailing_comma "$bkgs")"
            ;;

        DY|dy)
            era_datasets="$(strip_trailing_comma "$bkg_dy")"
            ;;

        tt|ttbar)
            era_datasets="$(strip_trailing_comma "$bkg_ttbar")"
            ;;

        singlet|single_top|single-top)
            era_datasets="$(strip_trailing_comma "$bkg_top")"
            ;;

        other_bkgs|other-bkgs|other)
            era_datasets="$(strip_trailing_comma "${bkg_wj}${bkg_vv}${bkg_vvv}${bkg_vh_htt}${bkg_higgs}")"
            ;;

        signal)
            era_datasets="$(strip_trailing_comma "$signal_all")"
            ;;

        ggphi|ggf)
            era_datasets="$(strip_trailing_comma "$signal_ggf")"
            ;;

        bbphi|bbh)
            era_datasets="$(strip_trailing_comma "$signal_bbh")"
            ;;

        datacard)
            # Full input needed for the final datacard distribution:
            # matching data + all backgrounds + only the signal(s) allowed by
            # the selected inference-model variant and mass.
            era_data="$(data_for_config "$cfg")"
            era_bkgs="$(strip_trailing_comma "$bkgs")"
            era_datasets="${era_data},${era_bkgs},${datacard_signal_datasets}"
            ;;

        *)
            echo "ERROR: unknown sample group '$sample_group'" >&2
            echo "Allowed: data, backgrounds, DY, tt, singlet, other_bkgs, signal, ggphi, bbphi, datacard" >&2
            exit 1
            ;;
    esac

    if [[ -n "$datasets_group" ]]; then
        datasets_group="${datasets_group}:"
    fi

    datasets_group="${datasets_group}${era_datasets}"
done

# =============================================================================
# Shift definitions
# =============================================================================

# JEC/JER are the only shifts that require distinct calibrated / selected /
# reduced event streams.
kinematic_shifts="nominal,jec_*,jer_*"

# These shifts require separate ProduceColumns / CreateHistograms /
# MergeHistograms tasks. Weight-only systematics are embedded into the
# nominal histogram by httcp_hist_producer and must not be scheduled as
# separate histogram tasks.
hist_shifts="${kinematic_shifts},unclustered_*,recoilresp_*,recoilres_*"

# Shift sources used by MergeShiftedHistograms / PlotShiftedVariables1D.
shift_sources_list=(
    "muon_weight"
    "electron_weight"
    "top_pt_weight"
    "Trigger_SF_weight"
    "zpt_weight"
    "pu_weight"
    "unclustered"

    "jec_Regrouped_Absolute"
    "jec_Regrouped_BBEC1"
    "jec_Regrouped_EC2"
    "jec_Regrouped_HF"
    "jec_Regrouped_RelativeBal"
    "jec_Regrouped_FlavorQCD"

    "jec_Regrouped_Absolute_*"
    "jec_Regrouped_BBEC1_*"
    "jec_Regrouped_EC2_*"
    "jec_Regrouped_HF_*"
    "jec_Regrouped_RelativeSample_*"

    "jer"

    "CMS_Scale_muR"
    "CMS_Scale_muF"
    "CMS_PS_ISR"
    "CMS_PS_FSR"

    "btag_weight_hf"
    "btag_weight_lf"
    "btag_weight_hfstats1"
    "btag_weight_hfstats2"
    "btag_weight_lfstats1"
    "btag_weight_lfstats2"
    "btag_weight_cferr1"
    "btag_weight_cferr2"

    "recoilresp"
    "recoilres"
)

shift_sources=$(IFS=,; echo "${shift_sources_list[*]}")

# Data is processed nominally only.
if [[ "$sample_group" == "data" ]]; then
    kinematic_shifts="nominal"
    hist_shifts="nominal"
fi

# =============================================================================
# Common command fragments
# =============================================================================

common_args=(
    --version "$version"
    --configs "$config"
    --datasets "$datasets_group"
    --poll-interval "5m"
    --pilot "True"
    --parallel-jobs 10
)

# PlotVariables1D and PlotShiftedVariables1D are not wrapper tasks, so keep a
# dedicated argument list and explicitly point their upstream requirements to
# the workflow used by the production chain.
prepare_plot_args() {
    plot_args=(
        --version "$version"
        --configs "$config"
        --datasets "$datasets_group"
        --poll-interval "1m"
        --pilot "True"

        --calibrators main
        --selector main

        --cf.CalibrateEvents-workflow "$workflow"
        --cf.SelectEvents-workflow "$workflow"
        --cf.ReduceEvents-workflow "$workflow"
        --cf.MergeReducedEvents-workflow "$workflow"
        --cf.ProduceColumns-workflow "$workflow"
        --cf.CreateHistograms-workflow "$workflow"
        --cf.MergeHistograms-workflow "$workflow"
    )

    # Process selection.
    if ! has_extra_option "--processes"; then
        plot_args+=(--processes "$plot_processes")
    fi

    # Variable/category/producer selection.
    if [[ "$sample_group" == "datacard" ]]; then
        if ! has_extra_option "--variables"; then
            plot_args+=(--variables "$datacard_variable")
        fi
        if ! has_extra_option "--categories"; then
            plot_args+=(--categories "$datacard_category")
        fi
        if ! has_extra_option "--producers"; then
            plot_args+=(--producers "$datacard_producers")
        fi

        # The inference model has add_qcd=True. Reproduce the same data-driven
        # QCD contribution in the diagnostic plot unless explicitly overridden.
        if ! has_extra_option "--hist-hooks"; then
            plot_args+=(--hist-hooks qcd)
        fi
    else
        if ! has_extra_option "--variables"; then
            plot_args+=(--variables "$variables")
        fi
        if [[ -n "${categories:-}" ]] && ! has_extra_option "--categories"; then
            plot_args+=(--categories "$categories")
        fi
        if ! has_extra_option "--producers"; then
            plot_args+=(--producers main)
        fi
    fi

    if ! has_extra_option "--file-types"; then
        plot_args+=(--file-types png)
    fi

    if ! has_extra_option "--general-settings"; then
        plot_args+=(--general-settings "cms-label=pw")
    fi
}

run_command() {
    echo
    echo "================================================================================"
    echo "Stage        : $stage"
    echo "Config option: $config_option"
    echo "Configs      : $config"
    echo "Sample group : $sample_group"

    if [[ "$sample_group" == "datacard" ]]; then
        echo "Variable     : $datacard_variable"
        echo "Category     : $datacard_category"
        echo "Mass         : $datacard_mass"
        echo "Producers    : $datacard_producers"
    fi

    echo "================================================================================"
    echo

    printf 'law run'
    printf ' %s' "$@"
    echo
    echo

    PYTHONFAULTHANDLER=1 law run "$@"
}

# =============================================================================
# Stage dispatch
# =============================================================================

case "$stage" in
    calibrate)
        run_command cf.CalibrateEventsWrapper \
            "${common_args[@]}" \
            --calibrator main \
            --shifts "$kinematic_shifts" \
            --cf.CalibrateEvents-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    select)
        run_command cf.SelectEventsWrapper \
            "${common_args[@]}" \
            --calibrators main \
            --selector main \
            --shifts "$kinematic_shifts" \
            --cf.SelectEvents-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    reduce)
        run_command cf.ReduceEventsWrapper \
            "${common_args[@]}" \
            --calibrators main \
            --selector main \
            --shifts "$kinematic_shifts" \
            --cf.ReduceEvents-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    merge-reduced)
        run_command cf.MergeReducedEventsWrapper \
            "${common_args[@]}" \
            --calibrators main \
            --selector main \
            --shifts "$kinematic_shifts" \
            --cf.MergeReducedEvents-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    produce)
        run_command cf.ProduceColumnsWrapper \
            "${common_args[@]}" \
            --producers main \
            --shifts "$hist_shifts" \
            --cf.ProduceColumns-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    create-hists)
        run_command cf.CreateHistogramsWrapper \
            "${common_args[@]}" \
            --calibrators main \
            --selector main \
            --producers main \
            --variables "$variables" \
            --shifts "$hist_shifts" \
            --cf.CreateHistograms-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    merge-hists)
        run_command cf.MergeHistogramsWrapper \
            "${common_args[@]}" \
            --calibrators main \
            --selector main \
            --producers main \
            --variables "$variables" \
            --shifts "$hist_shifts" \
            --cf.MergeHistograms-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    merge-shifted)
        if [[ "$sample_group" == "data" ]]; then
            echo "Data has no shifted histogram merge."
            echo "For data, stage 'merge-hists' with the nominal shift is the final histogram stage."
            exit 0
        fi

        run_command cf.MergeShiftedHistogramsWrapper \
            "${common_args[@]}" \
            --calibrators main \
            --selector main \
            --producers main \
            --variables "$variables" \
            --shift-sources "$shift_sources" \
            --cf.MergeShiftedHistograms-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    # -------------------------------------------------------------------------
    # Nominal 1D distributions
    # -------------------------------------------------------------------------
    plot1d)
        prepare_plot_args

        run_command cf.PlotVariables1D \
            "${plot_args[@]}" \
            --shift nominal \
            "${extra_args[@]}"
        ;;

    # -------------------------------------------------------------------------
    # Nominal + up/down variations for every requested shift source
    # -------------------------------------------------------------------------
    plot1d-shifted)
        prepare_plot_args

        plot_args+=(
            --cf.MergeShiftedHistograms-workflow "$workflow"
        )

        if ! has_extra_option "--shift-sources"; then
            plot_args+=(--shift-sources "$shift_sources")
        fi

        run_command cf.PlotShiftedVariables1D \
            "${plot_args[@]}" \
            "${extra_args[@]}"
        ;;

    *)
        echo "ERROR: unknown stage '$stage'" >&2
        echo "Allowed stages:" >&2
        echo "  calibrate, select, reduce, merge-reduced, produce," >&2
        echo "  create-hists, merge-hists, merge-shifted," >&2
        echo "  plot1d, plot1d-shifted" >&2
        exit 1
        ;;
esac
