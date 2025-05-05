# drugResponsePackage

## Overview

The `drugResponsePackage` is an R package designed for analyzing drug response data. It provides functions for data processing, summarization, and visualization of lab measurements and drug purchases.

## Installation

You can install the package from the local directory using the following command:

```R
devtools::install("path/to/drugResponsePackage")
```

## Usage

After installing the package, you can load it using:

```R
library(drugResponsePackage)
```

### Functions

The package includes several key functions:

- `create_drug_response()`: Generates a drug response dataset based on lab measurements and drug purchases.
- `generate_response_summary()`: Summarizes the response to drugs within specified time periods before and after drug purchases.
- `summarize_drug_response()`: Creates a summary PDF and text tables of drug response data.

## Examples

Here is a simple example of how to use the package:

```R
# Load the package
library(drugResponsePackage)




# Create drug response data
response_data <- create_drug_response(response, lab_measurements, drug_purchases, before_period, after_period)

# Generate a summary of the drug response
summary_data <- generate_response_summary(lab_measurements, before_period, after_period)

# Summarize and visualize the drug response
summarize_drug_response(response_data, "output_summary")
```

## Testing

The package includes unit tests to ensure the functionality of its core functions. You can run the tests using:

```R
devtools::test()
```

## Author

[Mitja Kurki]

## License

This package is licensed under the MIT License.