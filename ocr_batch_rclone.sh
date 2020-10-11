#!/usr/bin/env bash

# OK-API: Paperless-Office --> ocr_batch_rclone.sh
# Copyright (c) 2020
# Author: Norman Pausch
# Github Repository: ( https://github.com/OK-API/Paperless-Office)
# OK-API : O.K.-Automated Procedures Initiative.
#
# Rudimental script for OCR batch processing of picture or pdf files.
#
# This file is copyright under the version 1.2 (only) of the EUPL.
# Please see the LICENSE file for your rights under this license.

#
# 
# 

#########################################################################################################
# Help Section 																							#
# Main workflow:																						#
# 1. Copy files from remote to local dir (because of performance)										#
# 2. Convert files if necessary to suitable format for tesseracting, then tesseracting from inbox		#
# 3. Upload to remote and delete inbox                                                           	    #
#########################################################################################################


# Define Variables
DIR_REMOTE="onedrive:DigitaleAblage/InboxScan"		#Remote source directory for rsync/rclone
DIR_REMOTE_OCR="onedrive:DigitaleAblage/InboxOCR"			#Remote destination directory for rsync/rclone
DIR_INPUT="/mnt/750GB-USB/DigitaleAblage/InboxScan"					#Directory with not OCR scans
DIR_OUT="/mnt/750GB-USB/DigitaleAblage/InboxOCR"						#Directory for OCR-processed PDFs
LOCK_FILE="/mnt/750GB-USB/DigitaleAblage/InboxScan/ocr_batch.lck"	#Lock-file, for prohibit running script not in parallel when run from cron. In case of error/aborting this file must be deleted manually.
DIR_LOG="/mnt/750GB-USB/DigitaleAblage/logs"					#Directory for logfiles
LOG_SYNC=$DIR_LOG/rclone.log									#Logfile for verbose output from 'rsync'/'rclone'
LOG_OCR_BATCH=$DIR_LOG/ocr_batch_onedrive.log							#Logfile for general processing status
LOG_CONVERT=$DIR_LOG/converting.log								#Logfile for verbose output from 'convert'
LOG_TESSERACT=$DIR_LOG/tesseracting.log							#Logfile for verbose output from 'tesseract'
LOG_ERROR=$DIR_LOG/error.log									#Logfile for verbose output from STDERR


###BEGIN###

# Redirect errors STDERR
exec 2>> $LOG_ERROR 

# rename cannot use FQDN paths, wo we switch to path
cd $DIR_INPUT || exit

# check for LOCK file, abort if exist or create LOCK file if non is present
if [ -f $LOCK_FILE ]; then
		echo "$(date): $0 is already running ($LOCK_FILE exists). Exiting now." >> $LOG_OCR_BATCH 2>&1
		exit 1
		
	else
	#create LOCK file
	touch $LOCK_FILE 		
	
	# Copy remote inbox to local directory (because of performance processing)
	rclone --verbose move $DIR_REMOTE $DIR_INPUT >> $LOG_SYNC 2>&1
	
	# Find PDFs in local input directory and convert them to TIFF and delete PDFs
	find $DIR_INPUT -maxdepth 1 -type f -name '*.pdf' -print0 |
	while IFS= read -r -d '' file; do 
		convert -verbose -density 300 "${file}" -depth 8 -compress ZIP "${file%.*}".tif >> $LOG_CONVERT 2>&1
		rm -rf "${file}"
		echo "$(date): Converting file $file to TIF finished" >> $LOG_OCR_BATCH 2>&1
	done 
wait

	# Find TIFFs within input-dir and convert to new TIFF format (some scanner produce TIFF scans with older compression), because LibJpeg cancelled support for older JPEG compression
        find $DIR_INPUT -maxdepth 1 -type f -name '*.tif' -print0 |
	while IFS= read -r -d '' file; do
                convert -verbose "${file}"  "${file%.*}"_new.tif >> $LOG_CONVERT 2>&1
                rm -rf "${file}"
                echo "$(date): Converting file $file to NEW.TIF finished" >> $LOG_OCR_BATCH 2>&1
        done

wait

	# find TIFFs within input-dir and start OCR, rename, move to dir and delete
	find $DIR_INPUT -maxdepth 1 -type f -name '*.tif' -print0 |
	while IFS= read -r -d '' file; do 
		tesseract -l deu "${file}" "${file}" pdf >> $LOG_TESSERACT 2>&1; wait
		rename 's/\.tif\.pdf/-ocr\.pdf/' ./*; wait
		mv ./*-ocr.pdf "$DIR_OUT"; wait
		rm -rf "${file}"
		echo "$(date): Tesseracting file $file finished" >> $LOG_OCR_BATCH 2>&1
	done
	
	# Upload processed files and delete remote inbox
	rclone --verbose move $DIR_OUT $DIR_REMOTE_OCR >> $LOG_SYNC 2>&1; wait
#	rm -rf $LOCK_FILE  >> $LOG_RSYNC 2>&1
#	rm -rf $DIR_INPUT/* >> $LOG_RSYNC 2>&1
#	rm -rf $DIR_OUT/* >> $LOG_RSYNC 2>&1
#	rm -rf $DIR_REMOTE/InboxScan/* 2>&1
fi

wait
rm "$LOCK_FILE"		# delete LOCK file
