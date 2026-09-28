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
# Parallelism:
#
#   By default, all relevant remote ColumnFlow workflows are limited to
#   10 simultaneously active jobs.
#
#   Override globally for this invocation with:
#
#     ./MSSM_submit_stage.sh select 22and23_emu backgrounds --parallel-jobs 30
#
#   This script translates the generic --parallel-jobs option into the
#   task-family-specific ColumnFlow options, for example:
#
#     --cf.SelectEvents-parallel-jobs 30
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

# =============================================================================
# Parallel job handling
# =============================================================================

# Default maximum number of simultaneously active remote jobs.
parallel_jobs=10

# Keep all user-supplied LAW options, except the generic --parallel-jobs option.
#
# The generic option does not reliably propagate through ColumnFlow wrapper
# tasks. Therefore, intercept it here and later translate it into
# --cf.<TaskFamily>-parallel-jobs.
raw_extra_args=("$@")
extra_args=()

i=0

while (( i < ${#raw_extra_args[@]} )); do
    arg="${raw_extra_args[$i]}"

    case "$arg" in
        --parallel-jobs)

            if (( i + 1 >= ${#raw_extra_args[@]} )); then
                echo "ERROR: --parallel-jobs requires an integer argument." >&2
                exit 1
            fi

            parallel_jobs="${raw_extra_args[$((i + 1))]}"

            if ! [[ "$parallel_jobs" =~ ^[0-9]+$ ]]; then
                echo "ERROR: invalid value for --parallel-jobs: '$parallel_jobs'" >&2
                exit 1
            fi

            ((i += 2))
            ;;

        --parallel-jobs=*)

            parallel_jobs="${arg#--parallel-jobs=}"

            if ! [[ "$parallel_jobs" =~ ^[0-9]+$ ]]; then
                echo "ERROR: invalid value for --parallel-jobs: '$parallel_jobs'" >&2
                exit 1
            fi

            ((i += 1))
            ;;

        *)

            extra_args+=("$arg")
            ((i += 1))
            ;;
    esac
done

# =============================================================================
# ColumnFlow common setup
# =============================================================================

source "${SCRIPT_DIR}/common_run3_MSSM.sh"

set_common_vars "$config_option"

# =============================================================================
# Helpers
# =============================================================================

# Remove a trailing comma from dataset/process CSV strings.
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

# Check whether an option was explicitly supplied in extra_args.
#
# Supports both:
#
#   --option value
#
# and:
#
#   --option=value
#
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

datacard_discriminant=""
datacard_mass=""
datacard_category=""
datacard_producers=""
datacard_signal_datasets=""
datacard_signal_processes=""

# Process list corresponding exactly to the selected sample group.
case "$sample_group" in

    data)
        plot_processes="data"
        ;;

    backgrounds|background|bkg)
        plot_processes="dy_lep,dy_tt_m50,h_ggf_htt_sm_prod_sm,st,tt,h_vbf_htt_sm,vh_htt,wj,vv,vvv"
        ;;

    DY|dy)
        plot_processes="dy_lep,dy_tt_m50"
        ;;

    tt|ttbar)
        plot_processes="tt"
        ;;

    singlet|single_top|single-top)
        plot_processes="st"
        ;;

    other_bkgs|other-bkgs|other)
        plot_processes="h_ggf_htt_sm_prod_sm,h_vbf_htt_sm,vh_htt,wj,vv,vvv"
        ;;

    signal)
        plot_processes="$(strip_trailing_comma "$signal_all")"
        ;;

    ggphi|ggf)
        plot_processes="$(strip_trailing_comma "$signal_ggf")"
        ;;

    bbphi|bbh)
        plot_processes="$(strip_trailing_comma "$signal_bbh")"
        ;;

    datacard)
        # Filled below by the dedicated datacard logic.
        plot_processes=""
        ;;

    *)
        plot_processes="${processes:-}"
        ;;
esac

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
            datacard_category="cat_${datacard_channel}_sr__bdt_ggphi_and_bbphi_M${datacard_mass}"
            datacard_signal_datasets="ggphi_phitt_${datacard_mass}"
            datacard_signal_processes="ggphi_phitt_${datacard_mass}"
            ;;

        D_sig_vs_Disc_bbphi)
            datacard_category="cat_${datacard_channel}_sr__bdt_ggphi_and_bbphi_M${datacard_mass}"
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
    #
    #   main_common + bdt_card_<mass-block>
    #
    datacard_bdt_producer="$(
        python - "$datacard_mass" <<'PY'
import sys

from MSSM_H_tt.config.mass_points import get_bdt_card_producer_name

print(get_bdt_card_producer_name(int(sys.argv[1])))
PY
    )"

    datacard_producers="main_common,${datacard_bdt_producer}"

    datacard_background_processes="${processes_bkg:-data,dy_lep,dy_tt_m50,h_ggf_htt_sm_prod_sm,st,tt,h_vbf_htt_sm,vh_htt,wj,vv,vvv}"

    plot_processes="${datacard_background_processes},${datacard_signal_processes}"
fi

# =============================================================================
# Dataset splitting
# =============================================================================

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

# JEC/JER require distinct calibrated / selected / reduced event streams.
kinematic_shifts="nominal,jec_*,jer_*"

# These shifts require separate ProduceColumns / CreateHistograms /
# MergeHistograms tasks.
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
# Task-family-specific parallel job settings
# =============================================================================

# ColumnFlow's AnalysisTask.req_params() explicitly prefers these task-family
# parameters when propagating remote-workflow settings.
#
# Therefore, do not rely on:
#
#   --parallel-jobs 10
#
# alone.
#
# The options below control the actual remote workflow tasks.

parallel_args=()

add_parallel_arg() {
    local option="$1"

    # Allow an explicitly supplied task-family-specific option to override
    # the global default / generic --parallel-jobs value.
    if ! has_extra_option "$option"; then
        parallel_args+=("$option" "$parallel_jobs")
    fi
}

add_parallel_arg "--cf.CalibrateEvents-parallel-jobs"
add_parallel_arg "--cf.SelectEvents-parallel-jobs"
add_parallel_arg "--cf.ReduceEvents-parallel-jobs"
add_parallel_arg "--cf.MergeReducedEvents-parallel-jobs"
add_parallel_arg "--cf.ProduceColumns-parallel-jobs"
add_parallel_arg "--cf.CreateHistograms-parallel-jobs"
add_parallel_arg "--cf.MergeHistograms-parallel-jobs"
add_parallel_arg "--cf.MergeShiftedHistograms-parallel-jobs"

# =============================================================================
# Common command fragments
# =============================================================================

common_args=(
    --version "$version"
    --configs "$config"
    --datasets "$datasets_group"
    --pilot "True"

    "${parallel_args[@]}"
)

# PlotVariables1D and PlotShiftedVariables1D are not wrapper tasks, so keep a
# dedicated argument list and explicitly configure their upstream workflows.
prepare_plot_args() {

    plot_args=(
        --version "$version"
        --configs "$config"
        --datasets "$datasets_group"

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

        "${parallel_args[@]}"
    )

    # -------------------------------------------------------------------------
    # Process selection
    # -------------------------------------------------------------------------

    if ! has_extra_option "--processes"; then
        plot_args+=(--processes "$plot_processes")
    fi

    # -------------------------------------------------------------------------
    # Variable/category/producer selection
    # -------------------------------------------------------------------------

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

        # The inference model has add_qcd=True.
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

    # -------------------------------------------------------------------------
    # Output format
    # -------------------------------------------------------------------------

    if ! has_extra_option "--file-types"; then
        plot_args+=(--file-types png)
    fi

    # -------------------------------------------------------------------------
    # Plot settings
    # -------------------------------------------------------------------------

    if ! has_extra_option "--general-settings"; then
        plot_args+=(--general-settings "cms-label=pw")
    fi
}

# =============================================================================
# Command execution helper
# =============================================================================

run_command() {

    echo
    echo "================================================================================"
    echo "Stage          : $stage"
    echo "Config option  : $config_option"
    echo "Configs        : $config"
    echo "Sample group   : $sample_group"
    echo "Parallel jobs  : $parallel_jobs"

    if [[ "$sample_group" == "datacard" ]]; then
        echo "Variable       : $datacard_variable"
        echo "Category       : $datacard_category"
        echo "Mass           : $datacard_mass"
        echo "Producers      : $datacard_producers"
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

    # -------------------------------------------------------------------------
    # Calibration
    # -------------------------------------------------------------------------

    calibrate)

        run_command cf.CalibrateEventsWrapper \
            "${common_args[@]}" \
            --calibrator main \
            --shifts "$kinematic_shifts" \
            --cf.CalibrateEvents-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    # -------------------------------------------------------------------------
    # Selection
    # -------------------------------------------------------------------------

    select)

        run_command cf.SelectEventsWrapper \
            "${common_args[@]}" \
            --calibrators main \
            --selector main \
            --shifts "$kinematic_shifts" \
            --cf.SelectEvents-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    # -------------------------------------------------------------------------
    # ReduceEvents
    # -------------------------------------------------------------------------

    reduce)

        run_command cf.ReduceEventsWrapper \
            "${common_args[@]}" \
            --calibrators main \
            --selector main \
            --shifts "$kinematic_shifts" \
            --cf.ReduceEvents-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    # -------------------------------------------------------------------------
    # MergeReducedEvents
    # -------------------------------------------------------------------------

    merge-reduced)

        run_command cf.MergeReducedEventsWrapper \
            "${common_args[@]}" \
            --calibrators main \
            --selector main \
            --shifts "$kinematic_shifts" \
            --cf.MergeReducedEvents-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    # -------------------------------------------------------------------------
    # ProduceColumns
    # -------------------------------------------------------------------------

    produce)

        run_command cf.ProduceColumnsWrapper \
            "${common_args[@]}" \
            --producers main \
            --shifts "$hist_shifts" \
            --cf.ProduceColumns-workflow "$workflow" \
            "${extra_args[@]}"
        ;;

    # -------------------------------------------------------------------------
    # CreateHistograms
    # -------------------------------------------------------------------------

    create-hists)
        create_hists_args=(
            "${common_args[@]}"

            --calibrators main
            --selector main

            --shifts "$hist_shifts"

            --cf.CreateHistograms-workflow "$workflow"
        )

        if ! has_extra_option "--producers"; then
            create_hists_args+=(--producers main)
        fi

        if ! has_extra_option "--variables"; then
            create_hists_args+=(--variables "$variables")
        fi

        run_command cf.CreateHistogramsWrapper \
            "${create_hists_args[@]}" \
            "${extra_args[@]}"
        ;;

    # -------------------------------------------------------------------------
    # MergeHistograms
    # -------------------------------------------------------------------------

    merge-hists)
        merge_hists_args=(
            "${common_args[@]}"

            --calibrators main
            --selector main

            --shifts "$hist_shifts"

            --cf.MergeHistograms-workflow "$workflow"
        )

        if ! has_extra_option "--producers"; then
            merge_hists_args+=(--producers main)
        fi

        if ! has_extra_option "--variables"; then
            merge_hists_args+=(--variables "$variables")
        fi

        run_command cf.MergeHistogramsWrapper \
            "${merge_hists_args[@]}" \
            "${extra_args[@]}"
        ;;

    # -------------------------------------------------------------------------
    # MergeShiftedHistograms
    # -------------------------------------------------------------------------

    merge-shifted)
        if [[ "$sample_group" == "data" ]]; then
            echo "Data has no shifted histogram merge."
            echo "For data, stage 'merge-hists' with the nominal shift is the final histogram stage."
            exit 0
        fi

        merge_shifted_args=(
            "${common_args[@]}"
            --calibrators main
            --selector main
            --cf.MergeShiftedHistograms-workflow "$workflow"
        )

        if ! has_extra_option "--producers"; then
            merge_shifted_args+=(--producers main)
        fi

        if ! has_extra_option "--variables"; then
            merge_shifted_args+=(--variables "$variables")
        fi

        if ! has_extra_option "--shift-sources"; then
            merge_shifted_args+=(--shift-sources "$shift_sources")
        fi

        run_command cf.MergeShiftedHistogramsWrapper \
            "${merge_shifted_args[@]}" \
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
    # Nominal + up/down variations
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

    # -------------------------------------------------------------------------
    # Unknown stage
    # -------------------------------------------------------------------------

    *)

        echo "ERROR: unknown stage '$stage'" >&2

        echo "Allowed stages:" >&2
        echo "  calibrate, select, reduce, merge-reduced, produce," >&2
        echo "  create-hists, merge-hists, merge-shifted," >&2
        echo "  plot1d, plot1d-shifted" >&2

        exit 1
        ;;

esac