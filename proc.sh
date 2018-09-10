# This is the file structure and contents assumed:              
#  (NOTE: you can change names or run numbers as needed!)        
#       Experiment Folder                                        
#       --101 (subject folder)                                   
#       ----anat (folder containing the anatomical scans)        
#       ------struct+orig.BRIK & struct+orig.HEAD                
#       ----func (folder containing the functional scans)        
#       ------run1+orig.BRIK & run1+orig.HEAD                    
#       ------run2+orig.BRIK & run2+orig.HEAD                    
#       ----stim_times (folder containing your timing files)     
#       ------condition_01.1D                                    
#       ------condition_02.1D                                    
#       ------condition_03.1D  

#First, you need to bring your structural and functional files into AFNI using the to3d call and generate stimulus timing files. Then execute the current script to generate a preprocessing call using afni_proc.py. 
#-------------------------------------------A script to generate a preprocessing call ------------------------------

# Set subject and group identifiers
subj=$1
echo $subj
group_id=Con
echo $group_id

# Set data directories
top_dir="/tmp/yassamri/Exercise_Pattern_Separation/Reanalysis_Suwabe/Con/"
echo $top_dir
struct_dir="${top_dir}${subj}/struct/"
echo $struct_dir
func_dir="${top_dir}${subj}/func/"
echo $func_dir
stim_times_dir="${top_dir}${subj}/stim_times/"
echo $stim_times_dir

#  -dsets ${func_dir}raw_run1+orig.HEAD  ${func_dir}raw_run2+orig.HEAD${func_dir}raw_run3+orig.HEAD ${func_dir}raw_run4+orig.HEAD ${func_dir}raw_run5+orig.HEAD\

# run afni_proc.py to create a single subject processing script. For block, add "scale" after mask to normalize data and convert to percent change.

afni_proc.py -subj_id ${subj}\
	-script proc_${subj}.sh\
	-out_dir ${top_dir}${subj}/${subj}.${group_id}.preprocessed\
	-dsets ${func_dir}run_1+orig  ${func_dir}run_2+orig ${func_dir}run_3+orig ${func_dir}run_4+orig\
	-blocks tshift despike align tlrc volreg blur mask regress\
	-copy_anat ${struct_dir}struct+orig\
	-anat_has_skull yes\
	-tcat_remove_first_trs 0\
	-tshift_opts_ts -tpattern alt+z\
	-align_opts_aea -partial_axial -Allineate_opts '-warp aff -maxrot 45 -maxshf 45 -VERB -twopass -cubic -mast_dxyz 1.5'\
	-volreg_align_e2a\
	-volreg_align_to MIN_OUTLIER\
	-blur_size 2\
	-mask_apply anat\
	-regress_anaticor\
	-regress_3dD_stop\
        -regress_stim_times \
        ${stim_times_dir}TN.1D\
        ${stim_times_dir}TO.1D\
        ${stim_times_dir}LO.1D\
	${stim_times_dir}LS.1D\
	${stim_times_dir}sTN.1D\
        ${stim_times_dir}sTO.1D\
        ${stim_times_dir}sLO.1D\
        ${stim_times_dir}sLS.1D\
	${stim_times_dir}Junk.1D\
	-regress_stim_labels TargetNew TargetOld LureOld LureSimilar SubTargetNew SubTargetOld SubLureOld SubLureSimilar Junk\
	-regress_basis 'TENT(0,12,6)'\
	-regress_reml_exec\
	-regress_est_blur_epits\
	-regress_est_blur_errts\
	-regress_censor_outliers 0.1\
	-regress_censor_motion 0.3\
        -regress_apply_mot_types demean deriv\
	-regress_opts_3dD\
        -GOFORIT 3\
        -allzero_OK\
	-num_glt 10\
	-gltsym 'SYM: +TargetNew[1..4]' -glt_label 1 'TargetNew'\
	-gltsym 'SYM: +TargetOld[1..4]' -glt_label 2 'TargetOld'\
	-gltsym 'SYM: +LureOld[1..4]' -glt_label 3 'LureOld'\
	-gltsym 'SYM: +LureSimilar[1..4]' -glt_label 4 'LureSimilar'\
	-gltsym 'SYM: +SubTargetNew[1..4]' -glt_label 5 'SubTargetNew'\
	-gltsym 'SYM: +SubTargetOld[1..4]' -glt_label 6 'SubTargetOld'\
	-gltsym 'SYM: +SubLureOld[1..4]' -glt_label 7 'SubLureOld'\
	-gltsym 'SYM: +SubLureSimilar[1..4]' -glt_label 8 'SubLureSimilar'\
	-gltsym 'SYM: +SubLureSimilar[0..7] -SubLureOld[0..7]' -glt_label 9 "SubLureSimMinusOld" \
	-gltsym 'SYM: +LureSimilar[0..7] -LureOld[0..7]' -glt_label 10 "LureSimMinusOld" \
	-jobs 18\
