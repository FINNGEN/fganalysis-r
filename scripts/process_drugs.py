#!/usr/bin/env python3
import argparse

def main():
    parser = argparse.ArgumentParser(description="Process drug data.")
    parser.add_argument("input_file", type=str, help="Path to the input drug data file.")
    parser.add_argument("output_file", type=str, help="Path to save the processed drug data.")
    args = parser.parse_args()

    # Placeholder for processing logic
    print(f"Processing drug data from {args.input_file} and saving to {args.output_file}")


    with open(args.input_file, 'r') as infile, open(args.output_file, 'w') as outfile:
        header_idx = { col:i for i, col in enumerate(infile.readline().strip().split('\t')) }

        outfile.write('\t'.join(["FINNGENID", "APPROX_EVENT_DAY", "EVENT_AGE", "ATC", "VNR","MEDICATION_QUANTITY", "MERGED_SOURCE"]) + '\n')

        for line in infile:
            fields = line.strip().split('\t')
            FINNGENID = fields[header_idx['FINNGENID']]
            PRESCRIPTION_APPROX_EVENT_DAY = fields[header_idx['PRESCRIPTION_APPROX_EVENT_DAY']]
            PRESCRIPTION_AGE = fields[header_idx['PRESCRIPTION_AGE']]
            PRESCRIPTION_ATC_CODE = fields[header_idx['PRESCRIPTION_ATC']]
            PRESCRIPTION_VNR = fields[header_idx['PRESCRIPTION_VNR']]
            MEDICATION_APPROX_EVENT_DAY = fields[header_idx['MEDICATION_APPROX_EVENT_DAY']]
            MEDICATION_AGE = fields[header_idx['MEDICATION_AGE']]
            MEDICATION_ATC_CODE = fields[header_idx['MEDICATION_ATC']]
            MEDICATION_VNR = fields[header_idx['MEDICATION_VNR']]
            MEDICATION_QUANTITY = fields[header_idx['MEDICATION_QUANTITY']]    
            MERGED_SOURCE = fields[header_idx['MERGED_SOURCE']]

            AGE = MEDICATION_AGE
            VNR = MEDICATION_VNR
            EVENT_DAY = MEDICATION_APPROX_EVENT_DAY
            ATC_CODE = MEDICATION_ATC_CODE

            if MERGED_SOURCE == 'PRESCRIPTION' :
                continue

            if MEDICATION_AGE == '':
                AGE = PRESCRIPTION_AGE
                VNR = PRESCRIPTION_VNR
                EVENT_DAY = PRESCRIPTION_APPROX_EVENT_DAY
                ATC_CODE = PRESCRIPTION_ATC_CODE

            outfile.write('\t'.join([
                FINNGENID,
                EVENT_DAY,
                AGE,
                ATC_CODE,
                VNR,
                MEDICATION_QUANTITY,
                MERGED_SOURCE
            ]) + '\n')
                


if __name__ == "__main__":
    main()

    
