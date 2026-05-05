import re
import sys
import argparse
import gzip

FINNGENID = 'FINNGENID'
COLUMN = 'COLUMN'
VALUE = 'VALUE'

def print_progress_bar(iteration, total, prefix='', suffix='', length=50):
    percent = f"{100 * (iteration / float(total)):.1f}"
    filled_length = int(length * iteration // total)
    bar = '█' * filled_length + '-' * (length - filled_length)
    sys.stdout.write(f'\r{prefix} |{bar}| {percent}% {suffix}')
    sys.stdout.flush()
    if iteration == total:
        print()

def run(input_file, output_file, output_suffix_columns, ignore_columns):
    ignore_set = set(ignore_columns.split('|')) if ignore_columns else set()

    try:
        with gzip.open(input_file, 'r') as f:
            total_lines = sum(1 for _ in f) - 1

        matched_header = '_' + output_suffix_columns.replace('|', '|_')
        pattern = re.compile(fr'{matched_header}')
        sufficies = matched_header.split('|')
        provided_columns = output_suffix_columns.replace("|", "\t")

        with gzip.open(output_file, "wt", encoding="utf-8") as output:
            with gzip.open(input_file, 'rt') as file:
                header_line = file.readline().strip().split('\t')
                header_dict = {name: idx for idx, name in enumerate(header_line)}

                # Filter out suffix-matched columns, FINNGENID, and explicitly ignored columns
                filtered_header_data = {
                    k: v for k, v in header_dict.items()
                    if not pattern.search(k)
                    and k != FINNGENID
                    and k not in ignore_set
                }

                output_file_header = f"{FINNGENID}\t{COLUMN}\t{VALUE}\t{provided_columns}\n"
                output.write(output_file_header)

                for index, line in enumerate(file, start=1):
                    row = line.strip().split('\t')
                    for key, value in filtered_header_data.items():
                        resulting_row = []
                        resulting_row.append(row[header_dict[FINNGENID]])
                        resulting_row.append(key)
                        resulting_row.append(row[value])
                        if row[value] == 'NA':
                            continue
                        for suffix in sufficies:
                            prefix_column = f"{key}{suffix}"
                            resulting_row.append(row[header_dict[prefix_column]])
                        if len(resulting_row) == len(output_file_header.split('\t')):
                            output.write('\t'.join(resulting_row) + '\n')

                    if index % 100 == 0 or index == total_lines:
                        print_progress_bar(index, total_lines, prefix='Progress', suffix=f"{index}/{total_lines}", length=40)

        print('\nFinished successfully!')
    except Exception as e:
        print(f"An error occurred: {e}")
        raise

parser = argparse.ArgumentParser(description="Convert the wide format into long format!")
parser.add_argument('--input',   required=True, type=str, help="Input file in gzipped TSV wide format, e.g. path/to/input.tsv.gz")
parser.add_argument('--output',  required=True, type=str, help="Output file in gzipped TSV format, e.g. path/to/output.tsv.gz")
parser.add_argument('--suffixes', required=True, type=str, help="Pipe-separated endpoint metadata suffixes, e.g. FU_AGE|APPROX_EVENT_DAY|NEVT")
parser.add_argument('--ignore',  required=False, type=str, default='', help="Pipe-separated column names to ignore entirely, e.g. BL_AGE|BL_YEAR|AGE_AT_DEATH_OR_END_OF_FOLLOWUP|SEX")
args = parser.parse_args()

run(args.input, args.output, args.suffixes, args.ignore)
