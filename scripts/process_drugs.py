#!/usr/bin/env python3
import argparse
import gzip

def open_file(path, mode):
    if path.endswith('.gz'):
        return gzip.open(path, mode + 't', encoding='utf-8')
    return open(path, mode, encoding='utf-8')

def main():
    parser = argparse.ArgumentParser(description="Process drug data.")
    parser.add_argument("--input",  required=True, type=str, help="Path to the input drug data file.")
    parser.add_argument("--output", required=True, type=str, help="Path to save the processed drug data (use .gz extension for gzip output).")
    args = parser.parse_args()

    print(f"Processing drug data from {args.input} and saving to {args.output}")

    with open_file(args.input, 'r') as infile, open_file(args.output, 'w') as outfile:
        header_idx = {col: i for i, col in enumerate(infile.readline().strip().split('\t'))}
        outfile.write('\t'.join(["FINNGENID", "APPROX_EVENT_DAY", "EVENT_AGE", "ATC", "VNR", "MEDICATION_QUANTITY", "MERGED_SOURCE"]) + '\n')
        for line in infile:
            fields = line.strip().split('\t')
            FINNGENID                    = fields[header_idx['FINNGENID']]
            PRESCRIPTION_APPROX_EVENT_DAY = fields[header_idx['PRESCRIPTION_APPROX_EVENT_DAY']]
            PRESCRIPTION_AGE             = fields[header_idx['PRESCRIPTION_AGE']]
            PRESCRIPTION_ATC_CODE        = fields[header_idx['PRESCRIPTION_ATC']]
            PRESCRIPTION_VNR             = fields[header_idx['PRESCRIPTION_VNR']]
            MEDICATION_APPROX_EVENT_DAY  = fields[header_idx['MEDICATION_APPROX_EVENT_DAY']]
            MEDICATION_AGE               = fields[header_idx['MEDICATION_AGE']]
            MEDICATION_ATC_CODE          = fields[header_idx['MEDICATION_ATC']]
            MEDICATION_VNR               = fields[header_idx['MEDICATION_VNR']]
            MEDICATION_QUANTITY          = fields[header_idx['MEDICATION_QUANTITY']]
            MERGED_SOURCE                = fields[header_idx['MERGED_SOURCE']]

            if MERGED_SOURCE == 'PRESCRIPTION':
                continue

            AGE       = MEDICATION_AGE      if MEDICATION_AGE != ''  else PRESCRIPTION_AGE
            VNR       = MEDICATION_VNR      if MEDICATION_AGE != ''  else PRESCRIPTION_VNR
            EVENT_DAY = MEDICATION_APPROX_EVENT_DAY if MEDICATION_AGE != '' else PRESCRIPTION_APPROX_EVENT_DAY
            ATC_CODE  = MEDICATION_ATC_CODE if MEDICATION_AGE != ''  else PRESCRIPTION_ATC_CODE

            outfile.write('\t'.join([FINNGENID, EVENT_DAY, AGE, ATC_CODE, VNR, MEDICATION_QUANTITY, MERGED_SOURCE]) + '\n')

if __name__ == "__main__":
    main()

