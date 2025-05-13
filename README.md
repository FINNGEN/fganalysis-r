# Package for common analyses in FinnGen.

## Overview

The `fganalysis-r` is an R package designed for common analyses performed in FinnGen.  First functionality provides functions for data processing, summarization, and visualization of lab measurements and drug purchases.


## Installation

You can install the package from the local directory using the following command after installing `devtools` package:

Need to make precompiled packages of everything for sandbox.

```R
Some packages might get installed from source and to speedup that, can add multithreaded compilation.... add environment variable to enable 4 threads. 
Sys.setenv(MAKEFLAGS = "-j 4")
devtools::install("path/to/fganalysis")
```

## Usage

After installing the package, you can load it using:

```R
library("fganalysis-r")
```

### Functions

The package includes several key functions:

- `create_drug_response()`: Generates a drug response dataset based on lab measurements and drug purchases.
- `summarize_drug_response()`: Creates a summary PDF and text tables of drug response data.
- `get_lab_measurements` and `get_drug_purchases` to query for lab values and purchases.

## Examples

Here is a simple example of how to use the package:

```R
# Load the package
library(fganalysis-r)

## get connection to data sources.
conn <- connect_fgdata("config/db_config.json")

## get all labs with omopid 3007461
labs <- get_lab_measurements(conn$labs, c("3007461"))

## get all drug purchases with ATC codes starting with L01B
dr <- get_drug_purchases(conn$pheno, c("L01B"))


# Create drug response data of lab changes after initiating a drug.
## first define time intervals from drug purchase to summarise lab values
## here defining pre-measurements drug measurements to be 1 year before drug and 
## after period to be 1month to 1 year.
before_period <- c(-1, 0)
after_period <- c(1/12, 1)

## create a dataframe containing LDL (omopid 3001308) response to first statin purchase (ATC codes starting with A10) for each finngen ID  
resp <- create_drug_response(conn$labs,conn$pheno,c("3001308"), 
                             druglist=c("A10"),before_period,after_period)
## create plots and tables of the respons
summarize_drug_response(resp, out_file_prefix="3001308_A10_resp")

```


## Development &  Data storage


Install `devtools` package. When in root folder of package you can load everything with `devtools::load_all()`.  Read more about package dev with devtools here https://cran.r-project.org/web/packages/devtools/readme/README.html and https://r-pkgs.org/

Database connection is defined in config/db_config.json. Currently data is stored in parquet files and queried via duckdb. This way there are no external dependencies on databases.  
If new ways to access data are introduced, add handling of such datatypes in R/connections.R `connect_fgdata`. Returned objects should be lazy loaded dplyr::tbl objects so further processing can be done via dbplyr (https://dbplyr.tidyverse.org/)


### Testing


The package includes unit tests to ensure the functionality of its core functions. You can run the tests using:

```R
devtools::test()
```


When adding new functionality add unit tests. See tests/testthat/test-drug_response_functions.R for examples.

## Author

[Mitja Kurki]

## License

This package is licensed under the MIT License.
