#!/bin/bash

set_common_vars() {

version="dev"

case $1 in
    "run3ts_lim")
        config="run3_2022_preEE_tau_spinner_limited"
        datasets='h_ggf_htt_filtered' #,h_ggf_htt_unfiltered,zh_htt_unfiltered'
        processes='h_ggf_htt,data_mu' #,zh_htt'
        workflow='local'
    ;;
    "run3ts")
        config="run3_2022_preEE_tau_spinner"
        datasets='h_ggf_htt_filtered' #,h_ggf_htt_unfiltered,zh_htt_unfiltered'
        processes='h_ggf_htt' #,zh_htt'
        workflow='htcondor'
    ;;
    "run3_lim")
        config="run3_2022_preEE_limited"
        datasets='dy_incl' 
        processes='dy_z2mumu,dy_lep' 
        workflow='local'
    ;;
    "run3_wj_lim")
        config="run3_2022_preEE_limited"
        datasets='wj_incl' 
        processes='wj' 
        workflow='local'
    ;;
    "run3_dy_lim")
        config="run3_2022_preEE_limited"
        datasets='dy_incl' 
        processes='dy_lep' 
        workflow='local'
    ;;
    "run3_dy_wj")
        config="run3_2022_preEE"
        datasets='dy_incl,wj_incl' 
        processes='dy_lep,wj' 
        workflow='htcondor'
    ;;
    "run3_data")
        config="run3_2022_preEE"
        datasets='data_mu_C,data_mu_D,data_e_C,data_e_D,data_tau_C,data_tau_d' 
        processes='data' 
        workflow='htcondor'
    ;;
    "run3_data_tau_D")
        config="run3_2022_preEE_limited"
        datasets='data_tau_D' 
        processes='data_tau' 
        workflow='local'
    ;;
    "run3_data_tau_C")
        config="run3_2022_preEE_limited"
        datasets='data_tau_C' 
        processes='data_tau' 
        workflow='local'
    ;;
    "run3_data_dy_wj")
        config="run3_2022_preEE"
        datasets='data_mu_C,data_mu_D,data_e_C,data_e_D,data_tau_C,data_tau_D,dy_incl,wj_incl' 
        processes='data,dy_lep,wj' 
        workflow='local'
    ;;
    "run3_data_bkg")
    config="run3_2022_preEE"
    datasets='data_mu_C,data_mu_D,data_e_C,data_e_D,data_tau_C,data_tau_d,dy_incl,wj_incl' 
    processes='data,dy_lep,wj'
    workflow='local'
    ;;
    "run3_data_lim")
    config="run3_2022_preEE_limited"
    datasets='data_mu_C' 
    processes='data_mu' 
    workflow='local'
    ;;
    "run3_top_lim")
    config="run3_2022_preEE_limited"
    datasets='tt_sl' 
    processes='tt_sl' 
    workflow='local'
    ;;
    "run3")
        config="run3_2022_preEE"
        data='data_mu_C,data_mu_D,data_tau_C,data_tau_D,data_e_C,data_e_D,'
        bkg_ewk='wj_incl,ww,wz,zz,dy_incl,'
        bkg_top='st_twchannel_t_fh,st_twchannel_t_sl,st_twchannel_t_dl,st_twchannel_tbar_sl,st_twchannel_tbar_dl,st_tchannel_tbar,st_tchannel_t,st_schannel_tbar,st_schannel_t'
        bkg_ttbar='tt_sl,tt_dl,tt_fh'
        datasets="$data$bkg_ewk$bkg_top$bkg_ttbar"
        processes='dy_z2tautau,dy_z2mumu,dy_z2ee,vv,tt,st,wj,data'
        workflow='htcondor'
    ;;
    *)
    echo "Unknown run argument!"
    exit
    ;;
esac
}
