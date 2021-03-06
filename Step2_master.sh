#Step 2 Master Script

#Case Statement to test arguments
until [ -z $1 ];do
        case $1 in
        --dataset)
	shift
	dataset=$1;;
	--output)
        shift
        output=$1;;
	--strict)
	shift
	strict=$1;;
	--strict_num)
	shift
	strict_num=$1;;
	--spliced_beds)
	shift
	spliced_beds=$1;;
	--exon_GFF)
	shift
	exon_GFF=$1;;
	--intron_BED)
	shift
	intron_BED=$1;;
        -* )
        echo "unrecognised argument: $1"
        exit 1;;
esac
shift
if [ "$#" = "0" ]; then break; fi
        echo $1 $2
done

echo $output
echo $strict
echo $strict_num

## Concatenate all spliced intron bed files together and sort by start and coordinate
##
cat ${spliced_beds}/*spliced.introns.bed | sort -S 50% -k1,1 -k2,2n > ${output}.sorted.bed


#Strict mode - this is hard coded now. Merge cryptic tags if they are within 500bp of each other.
if [[ "$strict" == "yes" ]];then
	bedtools merge -i ${output}.sorted.bed -d ${strict_num} -c 1 -o count > ${output}.strict.${strict_num}.overlap.merged.bed
	bedtools subtract -a ${output}.strict.${strict_num}.overlap.merged.bed -b ${exon_GFF} > ${output}.strict.${strict_num}.merged.bed
	output=${output}.strict.${strict_num}

elif [[ "$strict" == "no" ]]; then
        
	bedtools merge -i ${output}.sorted.bed -c 1 -o count > ${output}.merged.bed
        
fi


## Intersect again. this removes intergenic spliced intervals and adds information about the intron that it intersects.
bedtools intersect -a ${output}.merged.bed -b ${intron_BED} -wb | awk 'BEGIN{OFS="\t"}{print $1,$2,$3,$4,$8,$9}' | sort -k1,1V -k5,5n > ${output}.cryptics.merged.bed


# add exon number
if [ -e ${output}.merged.annotated.bed ]; then rm ${output}.merged.annotated.bed;fi
## create unique list of gene/strand/intron_number and grep the merged list for each instance of that combination
## use awk to then append unique numbers on to each one
# for testing purposes just take the first 1000
cat ${output}.cryptics.merged.bed | awk '{print $6}' | sort -V | uniq > ${output}.unique_gene_introns.tab
date

# N is the number of allowed concurrently running forks
N=8

for entry in `cat ${output}.unique_gene_introns.tab`;do 
((i=i%N)); ((i++==0)) && wait
grep $entry ${output}.cryptics.merged.bed | awk 'BEGIN{s=1}{print $0"i"s;s+=1}' >> ${output}.merged.annotated.bed &
done
date

## Convert into a GFF file
cat ${output}.merged.annotated.bed | awk 'BEGIN{OFS="\t"}{split($6,a,"_");print $1, "mouse_iGenomes_GRCm38_with_ensembl.gtf", "exonic_part", $2, $3, ".", $5, ".", "transcripts \"cryptic_exon\"; exonic_part_number \""a[2]"\"; gene_id \""a[1]"\"" }' |
                sort -k1,1 -k2,2n > ${output}.cryptics.gff

## Place cryptic exons within the total exon GFF
cat ${output}.cryptics.gff ${exon_GFF}| sort -k1,1V -k4,4n -k5,5n | awk '$14 ~ /ENS/' > $output.total.cryptics.gff

exit
