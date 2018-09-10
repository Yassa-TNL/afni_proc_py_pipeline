#!/bin/tcsh -xef


#------------------------------------------------Preprocessing script-------------------------------------------------
echo "auto-generated by afni_proc.py, Fri May  6 13:48:00 2016"
echo "(version 4.58, January 27, 2016)"
echo "execution started: `date`"

# execute via : 
#   tcsh -xef proc_120.sh |& tee output.proc_120.sh

# =========================== auto block: setup ============================
# script setup

# take note of the AFNI version
afni -ver

# check that the current AFNI version is recent enough
afni_history -check_date 28 Oct 2015
if ( $status ) then
    echo "** this script requires newer AFNI binaries (than 28 Oct 2015)"
    echo "   (consider: @update.afni.binaries -defaults)"
    exit
endif

# the user may specify a single subject to run with
if ( $#argv > 0 ) then
    set subj = $argv[1]
else
    set subj = 120
endif

# assign output directory name
set output_dir = /tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/120/120.Con.preprocessed

# verify that the results directory does not yet exist
if ( -d $output_dir ) then
    echo output dir "$subj.results" already exists
    exit
endif

# set list of runs
set runs = (`count -digits 2 1 4`)

# create results and stimuli directories
mkdir $output_dir
mkdir $output_dir/stimuli

# copy stim files into stimulus directory
cp                                                                                         \
    /tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/120/stim_times/TN.1D   \
    /tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/120/stim_times/TO.1D   \
    /tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/120/stim_times/LO.1D   \
    /tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/120/stim_times/LS.1D   \
    /tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/120/stim_times/sTN.1D  \
    /tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/120/stim_times/sTO.1D  \
    /tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/120/stim_times/sLO.1D  \
    /tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/120/stim_times/sLS.1D  \
    /tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/120/stim_times/Junk.1D \
    $output_dir/stimuli

# copy anatomy to results dir
3dcopy 120/struct/struct+orig $output_dir/struct

# ============================ auto block: tcat ============================
# apply 3dTcat to copy input dsets to results dir, while
# removing the first 0 TRs
3dTcat -prefix $output_dir/pb00.$subj.r01.tcat 120/func/run_1+orig'[0..$]'
3dTcat -prefix $output_dir/pb00.$subj.r02.tcat 120/func/run_2+orig'[0..$]'
3dTcat -prefix $output_dir/pb00.$subj.r03.tcat 120/func/run_3+orig'[0..$]'
3dTcat -prefix $output_dir/pb00.$subj.r04.tcat 120/func/run_4+orig'[0..$]'

# and make note of repetitions (TRs) per run
set tr_counts = ( 180 180 180 180 )

# -------------------------------------------------------
# enter the results directory (can begin processing data)
cd $output_dir


# ========================== auto block: outcount ==========================
# data check: compute outlier fraction for each volume
touch out.pre_ss_warn.txt
foreach run ( $runs )
    3dToutcount -automask -fraction -polort 3 -legendre                     \
                pb00.$subj.r$run.tcat+orig > outcount.r$run.1D

    # censor outlier TRs per run, ignoring the first 0 TRs
    # - censor when more than 0.1 of automask voxels are outliers
    # - step() defines which TRs to remove via censoring
    1deval -a outcount.r$run.1D -expr "1-step(a-0.1)" > rm.out.cen.r$run.1D

    # outliers at TR 0 might suggest pre-steady state TRs
    if ( `1deval -a outcount.r$run.1D"{0}" -expr "step(a-0.4)"` ) then
        echo "** TR #0 outliers: possible pre-steady state TRs in run $run" \
            >> out.pre_ss_warn.txt
    endif
end

# catenate outlier counts into a single time series
cat outcount.r*.1D > outcount_rall.1D

# catenate outlier censor files into a single time series
cat rm.out.cen.r*.1D > outcount_${subj}_censor.1D

# get run number and TR index for minimum outlier volume
set minindex = `3dTstat -argmin -prefix - outcount_rall.1D\'`
set ovals = ( `1d_tool.py -set_run_lengths $tr_counts                       \
                          -index_to_run_tr $minindex` )
# save run and TR indices for extraction of min_outlier_volume
set minoutrun = $ovals[1]
set minouttr  = $ovals[2]
echo "min outlier: run $minoutrun, TR $minouttr" | tee out.min_outlier.txt

# ================================= tshift ===============================
# time shift data so all slice timing is the same 
foreach run ( $runs )
    3dTshift -tzero 0 -quintic -prefix pb01.$subj.r$run.tshift \
             -tpattern alt+z                                   \
             pb00.$subj.r$run.tcat+orig
end

# ================================ despike ===============================
# apply 3dDespike to each run
foreach run ( $runs )
    3dDespike -NEW -nomask -prefix pb02.$subj.r$run.despike \
        pb01.$subj.r$run.tshift+orig
end

# copy min outlier volume as registration base
3dbucket -prefix min_outlier_volume                         \
    pb02.$subj.r$minoutrun.despike+orig"[$minouttr]"

# ================================= align ================================
# for e2a: compute anat alignment transformation to EPI registration base
# (new anat will be intermediate, stripped, struct_ns+orig)
align_epi_anat.py -anat2epi -anat struct+orig                                \
       -save_skullstrip -suffix _al_junk                                     \
       -epi min_outlier_volume+orig -epi_base 0                              \
       -epi_strip 3dAutomask                                                 \
       -partial_axial -Allineate_opts '-warp aff -maxrot 45 -maxshf 45 -VERB \
       -twopass -cubic -mast_dxyz 1.5'                                       \
       -volreg off -tshift off

# ================================== tlrc ================================
# warp anatomy to standard space
@auto_tlrc -base TT_N27+tlrc -input struct_ns+orig -no_ss

# store forward transformation matrix in a text file
cat_matvec struct_ns+tlrc::WARP_DATA -I > warp.anat.Xat.1D

# ================================= volreg ===============================
# align each dset to base volume, align to anat

# register and warp
foreach run ( $runs )
    # register each volume to the base
    3dvolreg -verbose -zpad 1 -base min_outlier_volume+orig     \
             -1Dfile dfile.r$run.1D -prefix rm.epi.volreg.r$run \
             -cubic                                             \
             -1Dmatrix_save mat.r$run.vr.aff12.1D               \
             pb02.$subj.r$run.despike+orig

    # create an all-1 dataset to mask the extents of the warp
    3dcalc -overwrite -a pb02.$subj.r$run.despike+orig -expr 1  \
           -prefix rm.epi.all1

    # catenate volreg and epi2anat transformations
    cat_matvec -ONELINE                                         \
               struct_al_junk_mat.aff12.1D -I                   \
               mat.r$run.vr.aff12.1D > mat.r$run.warp.aff12.1D

    # apply catenated xform : volreg and epi2anat
    3dAllineate -base struct_ns+orig                            \
                -input pb02.$subj.r$run.despike+orig            \
                -1Dmatrix_apply mat.r$run.warp.aff12.1D         \
                -mast_dxyz 1.5                                  \
                -prefix rm.epi.nomask.r$run 

    # warp the all-1 dataset for extents masking 
    3dAllineate -base struct_ns+orig                            \
                -input rm.epi.all1+orig                         \
                -1Dmatrix_apply mat.r$run.warp.aff12.1D         \
                -mast_dxyz 1.5 -final NN -quiet                 \
                -prefix rm.epi.1.r$run 

    # make an extents intersection mask of this run
    3dTstat -min -prefix rm.epi.min.r$run rm.epi.1.r$run+orig

    # if there was an error, exit so user can see
    if ( $status ) exit

end

# make a single file of registration params
cat dfile.r*.1D > dfile_rall.1D

# ----------------------------------------
# create the extents mask: mask_epi_extents+orig
# (this is a mask of voxels that have valid data at every TR)
3dMean -datum short -prefix rm.epi.mean rm.epi.min.r*.HEAD 
3dcalc -a rm.epi.mean+orig -expr 'step(a-0.999)' -prefix mask_epi_extents

# and apply the extents mask to the EPI data 
# (delete any time series with missing data)
foreach run ( $runs )
    3dcalc -a rm.epi.nomask.r$run+orig -b mask_epi_extents+orig \
           -expr 'a*b' -prefix pb03.$subj.r$run.volreg
end

# create an anat_final dataset, aligned with stats
3dcopy struct_ns+orig anat_final.$subj

# -----------------------------------------
# warp anat follower datasets (affine)
3dAllineate -source struct+orig                                 \
            -master anat_final.$subj+orig                       \
            -final wsinc5 -1Dmatrix_apply warp.anat.Xat.1D      \
            -prefix anat_w_skull_warped

# ================================== blur ==============================
# blur each volume of each run
foreach run ( $runs )
    3dmerge -1blur_fwhm 2 -doall -prefix rm.pb04.$subj.r$run.blur    \
            pb03.$subj.r$run.volreg+orig

    # and apply extents mask, since no scale block
    3dcalc -a rm.pb04.$subj.r$run.blur+orig -b mask_epi_extents+orig \
           -expr 'a*b' -prefix pb04.$subj.r$run.blur
end

# ================================== mask===============================
# create 'full_mask' dataset (union mask)
foreach run ( $runs )
    3dAutomask -dilate 1 -prefix rm.mask_r$run pb04.$subj.r$run.blur+orig
end

# create union of inputs, output type is byte
3dmask_tool -inputs rm.mask_r*+orig.HEAD -union -prefix full_mask.$subj

# ---- create subject anatomy mask, mask_anat.$subj+orig ----
#      (resampled from aligned anat)
3dresample -master full_mask.$subj+orig -input struct_ns+orig        \
           -prefix rm.resam.anat

# convert to binary anat mask; fill gaps and holes
3dmask_tool -dilate_input 5 -5 -fill_holes -input rm.resam.anat+orig \
            -prefix mask_anat.$subj

# compute overlaps between anat and EPI masks
3dABoverlap -no_automask full_mask.$subj+orig mask_anat.$subj+orig   \
            |& tee out.mask_ae_overlap.txt

# note Dice coefficient of masks, as well
3ddot -dodice full_mask.$subj+orig mask_anat.$subj+orig              \
      |& tee out.mask_ae_dice.txt

# ---- segment anatomy into classes CSF/GM/WM ----
3dSeg -anat anat_final.$subj+orig -mask AUTO -classes 'CSF ; GM ; WM'

# copy resulting Classes dataset to current directory
3dcopy Segsy/Classes+orig .

# make individual ROI masks for regression (CSF GM WM and CSFe GMe WM)
foreach class ( CSF GM WM )
   # unitize and resample individual class mask from composite
   3dmask_tool -input Segsy/Classes+orig"<$class>"                   \
               -prefix rm.mask_${class}
   3dresample -master pb04.$subj.r01.blur+orig -rmode NN             \
              -input rm.mask_${class}+orig -prefix mask_${class}_resam
   # also, generate eroded masks
   3dmask_tool -input Segsy/Classes+orig"<$class>" -dilate_input -1  \
               -prefix rm.mask_${class}e
   3dresample -master pb04.$subj.r01.blur+orig -rmode NN             \
              -input rm.mask_${class}e+orig -prefix mask_${class}e_resam
end

# ================================ regress ===============================

# compute de-meaned motion parameters (for use in regression)
1d_tool.py -infile dfile_rall.1D -set_nruns 4                                 \
           -demean -write motion_demean.1D

# compute motion parameter derivatives (for use in regression)
1d_tool.py -infile dfile_rall.1D -set_nruns 4                                 \
           -derivative -demean -write motion_deriv.1D

# create censor file motion_${subj}_censor.1D, for censoring motion 
1d_tool.py -infile dfile_rall.1D -set_nruns 4                                 \
    -show_censor_count -censor_prev_TR                                        \
    -censor_motion 0.3 motion_${subj}

# combine multiple censor files
1deval -a motion_${subj}_censor.1D -b outcount_${subj}_censor.1D              \
       -expr "a*b" > censor_${subj}_combined_2.1D

# note TRs that were not censored
set ktrs = `1d_tool.py -infile censor_${subj}_combined_2.1D                   \
                       -show_trs_uncensored encoded`

# ------------------------------
# run the regression analysis
3dDeconvolve -input pb04.$subj.r*.blur+orig.HEAD                              \
    -mask mask_anat.$subj+orig                                                \
    -censor censor_${subj}_combined_2.1D                                      \
    -polort 3 -float                                                          \
    -num_stimts 21                                                            \
    -stim_times 1 stimuli/TN.1D 'TENT(0,12,6)'                                \
    -stim_label 1 TargetNew                                                   \
    -stim_times 2 stimuli/TO.1D 'TENT(0,12,6)'                                \
    -stim_label 2 TargetOld                                                   \
    -stim_times 3 stimuli/LO.1D 'TENT(0,12,6)'                                \
    -stim_label 3 LureOld                                                     \
    -stim_times 4 stimuli/LS.1D 'TENT(0,12,6)'                                \
    -stim_label 4 LureSimilar                                                 \
    -stim_times 5 stimuli/sTN.1D 'TENT(0,12,6)'                               \
    -stim_label 5 SubTargetNew                                                \
    -stim_times 6 stimuli/sTO.1D 'TENT(0,12,6)'                               \
    -stim_label 6 SubTargetOld                                                \
    -stim_times 7 stimuli/sLO.1D 'TENT(0,12,6)'                               \
    -stim_label 7 SubLureOld                                                  \
    -stim_times 8 stimuli/sLS.1D 'TENT(0,12,6)'                               \
    -stim_label 8 SubLureSimilar                                              \
    -stim_times 9 stimuli/Junk.1D 'TENT(0,12,6)'                              \
    -stim_label 9 Junk                                                        \
    -stim_file 10 motion_demean.1D'[0]' -stim_base 10 -stim_label 10 roll_01  \
    -stim_file 11 motion_demean.1D'[1]' -stim_base 11 -stim_label 11 pitch_01 \
    -stim_file 12 motion_demean.1D'[2]' -stim_base 12 -stim_label 12 yaw_01   \
    -stim_file 13 motion_demean.1D'[3]' -stim_base 13 -stim_label 13 dS_01    \
    -stim_file 14 motion_demean.1D'[4]' -stim_base 14 -stim_label 14 dL_01    \
    -stim_file 15 motion_demean.1D'[5]' -stim_base 15 -stim_label 15 dP_01    \
    -stim_file 16 motion_deriv.1D'[0]' -stim_base 16 -stim_label 16 roll_02   \
    -stim_file 17 motion_deriv.1D'[1]' -stim_base 17 -stim_label 17 pitch_02  \
    -stim_file 18 motion_deriv.1D'[2]' -stim_base 18 -stim_label 18 yaw_02    \
    -stim_file 19 motion_deriv.1D'[3]' -stim_base 19 -stim_label 19 dS_02     \
    -stim_file 20 motion_deriv.1D'[4]' -stim_base 20 -stim_label 20 dL_02     \
    -stim_file 21 motion_deriv.1D'[5]' -stim_base 21 -stim_label 21 dP_02     \
    -iresp 1 iresp_TargetNew.$subj                                            \
    -iresp 2 iresp_TargetOld.$subj                                            \
    -iresp 3 iresp_LureOld.$subj                                              \
    -iresp 4 iresp_LureSimilar.$subj                                          \
    -iresp 5 iresp_SubTargetNew.$subj                                         \
    -iresp 6 iresp_SubTargetOld.$subj                                         \
    -iresp 7 iresp_SubLureOld.$subj                                           \
    -iresp 8 iresp_SubLureSimilar.$subj                                       \
    -iresp 9 iresp_Junk.$subj                                                 \
    -GOFORIT 3                                                                \
    -allzero_OK                                                               \
    -num_glt 10                                                               \
    -gltsym 'SYM: +TargetNew[1..4]'                                           \
    -glt_label 1 TargetNew                                                    \
    -gltsym 'SYM: +TargetOld[1..4]'                                           \
    -glt_label 2 TargetOld                                                    \
    -gltsym 'SYM: +LureOld[1..4]'                                             \
    -glt_label 3 LureOld                                                      \
    -gltsym 'SYM: +LureSimilar[1..4]'                                         \
    -glt_label 4 LureSimilar                                                  \
    -gltsym 'SYM: +SubTargetNew[1..4]'                                        \
    -glt_label 5 SubTargetNew                                                 \
    -gltsym 'SYM: +SubTargetOld[1..4]'                                        \
    -glt_label 6 SubTargetOld                                                 \
    -gltsym 'SYM: +SubLureOld[1..4]'                                          \
    -glt_label 7 SubLureOld                                                   \
    -gltsym 'SYM: +SubLureSimilar[1..4]'                                      \
    -glt_label 8 SubLureSimilar                                               \
    -gltsym 'SYM: +SubLureSimilar[0..7] -SubLureOld[0..7]'                    \
    -glt_label 9 SubLureSimMinusOld                                           \
    -gltsym 'SYM: +LureSimilar[0..7] -LureOld[0..7]'                          \
    -glt_label 10 LureSimMinusOld                                             \
    -jobs 18                                                                  \
    -fout -tout -x1D X.xmat.1D -xjpeg X.jpg                                   \
    -x1D_uncensored X.nocensor.xmat.1D                                        \
    -fitts fitts.$subj                                                        \
    -errts errts.${subj}                                                      \
    -x1D_stop                                                                 \
    -bucket stats.$subj


# if 3dDeconvolve fails, terminate the script
if ( $status != 0 ) then
    echo '---------------------------------------'
    echo '** 3dDeconvolve error, failing...'
    echo '   (consider the file 3dDeconvolve.err)'
    exit
endif


# display any large pairwise correlations from the X-matrix
1d_tool.py -show_cormat_warnings -infile X.xmat.1D |& tee out.cormat_warn.txt

# look for odd timing in files for TENT functions
timing_tool.py -multi_timing stimuli/TN.1D                                    \
                             stimuli/TO.1D                                    \
                             stimuli/LO.1D                                    \
                             stimuli/LS.1D                                    \
                             stimuli/sTN.1D                                   \
                             stimuli/sTO.1D                                   \
                             stimuli/sLO.1D                                   \
                             stimuli/sLS.1D                                   \
                             stimuli/Junk.1D                                  \
               -tr 2.0 -warn_tr_stats |& tee out.TENT_warn.txt

# --------------------------------------------------
# ANATICOR: generate local WMe time series averages
# create catenated volreg dataset
3dTcat -prefix rm.all_runs.volreg pb03.$subj.r*.volreg+orig.HEAD
3dLocalstat -stat mean -nbhd 'SPHERE(45)' -prefix Local_WMe_rall              \
            -mask mask_WMe_resam+orig -use_nonmask                            \
            rm.all_runs.volreg+orig

# -- execute the 3dREMLfit script, written by 3dDeconvolve --
# (include ANATICOR regressors via -dsort)
tcsh -x stats.REML_cmd -dsort Local_WMe_rall+orig 

# if 3dREMLfit fails, terminate the script
if ( $status != 0 ) then
    echo '---------------------------------------'
    echo '** 3dREMLfit error, failing...'
    exit
endif


# create an all_runs dataset to match the fitts, errts, etc.
3dTcat -prefix all_runs.$subj pb04.$subj.r*.blur+orig.HEAD

# --------------------------------------------------
# create a temporal signal to noise ratio dataset 
#    signal: if 'scale' block, mean should be 100
#    noise : compute standard deviation of errts
3dTstat -mean -prefix rm.signal.all all_runs.$subj+orig"[$ktrs]"
3dTstat -stdev -prefix rm.noise.all errts.${subj}_REML+orig"[$ktrs]"
3dcalc -a rm.signal.all+orig                                                  \
       -b rm.noise.all+orig                                                   \
       -c mask_anat.$subj+orig                                                \
       -expr 'c*a/b' -prefix TSNR.$subj 

# ---------------------------------------------------
# compute and store GCOR (global correlation average)
# (sum of squares of global mean of unit errts)
3dTnorm -norm2 -prefix rm.errts.unit errts.${subj}_REML+orig
3dmaskave -quiet -mask full_mask.$subj+orig rm.errts.unit+orig                \
          > gmean.errts.unit.1D
3dTstat -sos -prefix - gmean.errts.unit.1D\' > out.gcor.1D
echo "-- GCOR = `cat out.gcor.1D`"

# ---------------------------------------------------
# compute correlation volume
# (per voxel: average correlation across masked brain)
# (now just dot product with average unit time series)
3dcalc -a rm.errts.unit+orig -b gmean.errts.unit.1D -expr 'a*b' -prefix rm.DP
3dTstat -sum -prefix corr_brain rm.DP+orig

# --------------------------------------------------------
# compute sum of non-baseline regressors from the X-matrix
# (use 1d_tool.py to get list of regressor colums)
set reg_cols = `1d_tool.py -infile X.nocensor.xmat.1D -show_indices_interest`
3dTstat -sum -prefix sum_ideal.1D X.nocensor.xmat.1D"[$reg_cols]"

# also, create a stimulus-only X-matrix, for easy review
1dcat X.nocensor.xmat.1D"[$reg_cols]" > X.stim.xmat.1D

# ============================ blur estimation =============================
# compute blur estimates
touch blur_est.$subj.1D   # start with empty file

# -- estimate blur for each run in epits --
touch blur.epits.1D

# restrict to uncensored TRs, per run
foreach run ( $runs )
    set trs = `1d_tool.py -infile X.xmat.1D -show_trs_uncensored encoded      \
                          -show_trs_run $run`
    if ( $trs == "" ) continue
    3dFWHMx -detrend -mask mask_anat.$subj+orig                               \
        all_runs.$subj+orig"[$trs]" >> blur.epits.1D
end

# compute average blur and append
set blurs = ( `3dTstat -mean -prefix - blur.epits.1D\'` )
echo average epits blurs: $blurs
echo "$blurs   # epits blur estimates" >> blur_est.$subj.1D

# -- estimate blur for each run in err_reml --
touch blur.err_reml.1D

# restrict to uncensored TRs, per run
foreach run ( $runs )
    set trs = `1d_tool.py -infile X.xmat.1D -show_trs_uncensored encoded      \
                          -show_trs_run $run`
    if ( $trs == "" ) continue
    3dFWHMx -detrend -mask mask_anat.$subj+orig                               \
        errts.${subj}_REML+orig"[$trs]" >> blur.err_reml.1D
end

# compute average blur and append
set blurs = ( `3dTstat -mean -prefix - blur.err_reml.1D\'` )
echo average err_reml blurs: $blurs
echo "$blurs   # err_reml blur estimates" >> blur_est.$subj.1D


# add 3dClustSim results as attributes to any stats dset
set fxyz = ( `tail -1 blur_est.$subj.1D` )
3dClustSim -both -mask mask_anat.$subj+orig -fwhmxyz $fxyz[1-3]               \
           -prefix ClustSim
set cmd = ( `cat 3dClustSim.cmd` )
$cmd stats.${subj}_REML+orig


# ================== auto block: generate review scripts ===================

# generate a review script for the unprocessed EPI data
gen_epi_review.py -script @epi_review.$subj \
    -dsets pb00.$subj.r*.tcat+orig.HEAD

# generate scripts to review single subject results
# (try with defaults, but do not allow bad exit status)
gen_ss_review_scripts.py -mot_limit 0.3 -out_limit 0.1 -exit0

# ========================== auto block: finalize ==========================

# remove temporary files
\rm -fr rm.* Segsy

# if the basic subject review script is here, run it
# (want this to be the last text output)
if ( -e @ss_review_basic ) ./@ss_review_basic |& tee out.ss_review.$subj.txt

# return to parent directory
cd ..
echo "execution finished: `date`"