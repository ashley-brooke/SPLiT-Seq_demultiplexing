#$ -V -cwd -j y -o -/home/ranump/ -m e -M ranump@email.chop.edu -q all.q -pe smp 20
#!/bin/bash

# Provide the number of cores for multiplex steps
numcores="12"

# Provide the filenames of the .csv files that contain the barcode sequences. These files should be located in the working directory.
ROUND1="Round1_barcodes_new2.txt"
ROUND2="Round2_barcodes_new2.txt"
ROUND3="Round3_barcodes_new2.txt"

# Provide the filenames of the .fastq files of interest. For this experiment paired end reads are required.
FASTQ_F="SRR6750041_1_bigtest.fastq"
FASTQ_R="SRR6750041_2_bigtest.fastq"

# Add the barcode sequences to a bash array.
declare -a ROUND1_BARCODES=( $(cut -b 1- $ROUND1) )
#printf "%s\n" "${ROUND1_BARCODES[@]}"

declare -a ROUND2_BARCODES=( $(cut -b 1- $ROUND2) )
#printf "%s\n" "${ROUND2_BARCODES[@]}"

declare -a ROUND3_BARCODES=( $(cut -b 1- $ROUND3) )
#printf "%s\n" "${ROUND3_BARCODES[@]}"

# Initialize the counter
count=1

# Create a log file
rm outputLOG
touch outputLOG

# Log current time
now=$(date +"%T")
echo "Current time : $now" >> outputLOG

# Make folder for results files
mkdir results


#######################################
# STEP 1: Demultiplex using barcodes  #
#######################################
# Search for the barcode in the sample reads file
# Use a for loop to iterate a search for each barcode.  If a match for the first barcode is found search for a match for a second barcode. If a match for the second barcode is found search through the third list of barcodes.

# Generate a progress message
now=$(date +"%T")
echo "Beginning STEP1: Demultiplex using barcodes. Current time : $now" >> outputLOG

# Clean up by removing results files that may have been generated by a previous run.
rm -r ROUND*
rm results/result*
rm -r parallel_results

# Begin the set of nested loops that searches for every possible barcode. We begin by looking for ROUND1 barcodes 
for barcode1 in "${ROUND1_BARCODES[@]}";
    do
    grep -B 1 -A 2 "$barcode1" $FASTQ_R > ROUND1_MATCH.fastq
    echo barcode1.is.$barcode1 >> outputLOG
    
        if [ -s ROUND1_MATCH.fastq ]
        then
            
            # Now we will look for the presence of ROUND2 barcodes in our reads containing barcodes from the previous step
            for barcode2 in "${ROUND2_BARCODES[@]}";
            do
            grep -B 1 -A 2 "$barcode2" ROUND1_MATCH.fastq > ROUND2_MATCH.fastq
               
                if [ -s ROUND2_MATCH.fastq ]
                then

                    # Now we will look for the presence of ROUND3 barcodes in our reads containing barcodes from the previous step 
                    for barcode3 in "${ROUND3_BARCODES[@]}";
                    do
                    grep -B 1 -A 2 "$barcode3" ./ROUND2_MATCH.fastq | sed '/^--/d' > ROUND3_MATCH.fastq

                    # If matches are found we will write them to an output .fastq file itteratively labelled with an ID number
                    if [ -s ROUND3_MATCH.fastq ]
                    then
                    mv ROUND3_MATCH.fastq results/result.$count.2.fastq
                    fi

                    count=`expr $count + 1`
                    done
                fi
            done
        fi
    done

find results/ -size  0 -print0 |xargs -0 rm --

# Parallelize nested loops
#now=$(date +"%T")
#echo "Beginning STEP1.2: PARALLEL Demultiplex using barcodes. Current time : $now" >> outputLOG

#mkdir ROUND1_PARALLEL_HITS
#parallel -j 6 'grep -B 1 -A 2 -h {} SRR6750041_2_smalltest.fastq > ROUND1_PARALLEL_HITS/{#}_ROUND1_MATCH.fastq' ::: "${ROUND1_BARCODES[@]}"

#mkdir ROUND2_PARALLEL_HITS
#parallel -j 6 'grep -B 1 -A 2 -h {} ROUND1_PARALLEL_HITS/*.fastq > ROUND2_PARALLEL_HITS/{#}_{/.}.fastq' ::: "${ROUND2_BARCODES[@]}"

#mkdir ROUND3_PARALLEL_HITS
#parallel -j 6 'grep -B 1 -A 2 -h {} ROUND2_PARALLEL_HITS/*.fastq > ROUND3_PARALLEL_HITS/{#}_{/.}.fastq' ::: "${ROUND3_BARCODES[@]}"

#mkdir parallel_results
#parallel -j 6 'mv {} parallel_results/result_{#}.fastq' ::: ROUND3_PARALLEL_HITS/*.fastq

#find parallel_results/ -size  0 -print0 |xargs -0 rm --


##########################################################
# STEP 2: For every cell find matching paired end reads  #
##########################################################
# Generate a progress message
now=$(date +"%T")
echo "Beginning STEP2: finding read mate pairs. Current time" : $now >> outputLOG

# Now we need to collect the other read pair. To do this we can collect read IDs from the results files we generated in step one.
# Generate an array of cell filenames
declare -a cells=( $(ls results/) )

# Loop through the cell files in order to extract the read IDs for each cell
#for cell in "${cells[@]}";
#    do 
#    grep -Eo '@[^ ]+' results/$cell > readIDs.txt # Grep for only the first word 
#    declare -a readID=( $(grep -Eo '^@[^ ]+' results/$cell) )
#        for ID in "${readID[@]}";
#        do
#        grep -A 3 "$ID " $FASTQ_F | sed '/^--/d' >> results/$cell.MATEPAIR # Write the mate paired reads to a file
#        done
#    done

# Parallelize mate pair finding
for cell in "${cells[@]}";
    do 
    grep -Eo '@[^ ]+' results/$cell > readIDs.txt # Grep for only the first word 
    declare -a readID=( $(grep -Eo '^@[^ ]+' results/$cell) )
        
       
        grepfunction2() {
        grep -A 3 "$1 " $2 | sed '/^--/d'
        }
        export -f grepfunction2
        
        parallel -j $numcores "grepfunction2 {} $FASTQ_F >> results/$cell.MATEPAIR" ::: "${readID[@]}" # Write the mate paired reads to a file
    done


########################
# STEP 3: Extract UMIs #
########################
# Generate a progress message
now=$(date +"%T")
echo "Beginning STEP3: Extracting UMIs. Current time : $now" >> outputLOG

rm -r results_UMI
mkdir results_UMI

###
# Parallelize UMI extraction

parallel -j $numcores 'umi_tools extract -I {} --read2-in={}.MATEPAIR --bc-pattern=NNNNNNNNNN --log=processed.log --read2-out=results_UMI/{/}.read2.fastq' ::: results/result.*.fastq
parallel -j $numcores 'mv {} results_UMI/cell_{#}.fastq' ::: results_UMI/*.fastq
###

#rm -r results_UMI
#mkdir results_UMI

#for cell in "${cells[@]}";
#    do
#        umi_tools extract -I results/$cell \
#        --read2-in=results/$cell.MATEPAIR \
#        --bc-pattern=NNNNNNNNNN \
#        --log=processed.log \
#        --stdout=results_UMI/$cell.read1.fastq \
#        --read2-out=results_UMI/$cell.read2.fastq
#    done 

#rm -r results
#rm results_UMI/*.read1.fastq

#All finished
number_of_cells=$(ls -1 results_UMI | wc -l)
now=$(date +"%T")
echo "a total of $number_of_cells cells were demultiplexed from the input .fastq" >> outputLOG
echo "Current time : $now" >> outputLOG
echo "all finished goodbye" >> outputLOG
