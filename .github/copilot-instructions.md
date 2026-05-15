# Copilot Instructions for fganalysis-r

## Repository Overview

**fganalysis** is an R package for drug response analysis in FinnGen, providing functions for data processing, summarization, and visualization of lab measurements and drug purchases. The package uses DuckDB to query parquet-formatted data and implements BLUP/Linear Mixed Models for longitudinal analysis.

- **Type**: R package (approximately 2,000 lines of R code)
- **Language**: R (primary), with helper scripts in Python and Bash
- **Version**: 0.2.3
- **Key Dependencies**: dplyr, ggplot2, duckdb, duckdbfs, lme4, ggpubr, testthat
- **Testing Framework**: testthat (4 test files, ~1,300 lines of tests)

## Project Structure

### R Source Files (`R/`)
The package follows a modular architecture with 6 core files (~2,000 lines total):

- **`connections.R`** (203 lines) - Database connection management for DuckDB/BigQuery
- **`data_access.R`** (268 lines) - Data retrieval functions for labs and drugs
- **`drug_response_core.R`** (448 lines) - Core drug response analysis and S3 object creation
- **`visualization.R`** (285 lines) - Plotting functions (ggplot2, UpSetR)
- **`blup_analysis.R`** (495 lines) - BLUP/Linear Mixed Model implementation
- **`qc_functions.R`** (354 lines) - Quality control, normalization, variance processing

### Configuration Files
- **`.lintr`** - Linter configuration (indentation = 4 spaces, no line length limit)
- **`.Rbuildignore`** - Build exclusions (`.github/`, `scripts/`, PDF files)
- **`.gitignore`** - Excludes `.Rcheck/`, output directories, local config files
- **`config/db_config.json`** - Data source paths for Google Cloud Storage parquet files
- **`config/db_config_sb.json`** - Sandbox environment configuration

### Tests (`tests/testthat/`)
- **`test-drug_response_functions.R`** (118 lines) - Tests for drug.response S3 class
- **`test-blup_analysis.R`** (422 lines) - BLUP slope calculation tests
- **`test-get_measurements_before_drug.R`** (546 lines) - Data retrieval tests
- **`test-qc_functions.R`** (200 lines) - QC and normalization tests

### Documentation
- **`README.md`** - Comprehensive package documentation with examples
- **`man/`** - Roxygen2-generated documentation (RoxygenNote: 7.3.2)
- **`DESCRIPTION`** - Package metadata, dependencies, and version

### Scripts (`scripts/`) - NOT part of the package
- **`prepare_data.sh`** - DuckDB data preparation commands
- **`process_drugs.py`** - Python script for drug event processing
- **`plot_blup_correlation.R`** - Example analysis script

## Build & Test Workflow

### CI/CD Pipeline (`.github/workflows/r.yml`)
The GitHub Actions workflow runs `R CMD check` on every push/PR:
- **Platform**: ubuntu-latest with R release version
- **Uses**: `r-lib/actions` standard workflow
- **Command**: `r-lib/actions/check-r-package@v2` (runs `R CMD check`)
- **Key steps**: 
  1. Checkout code
  2. Setup R and pandoc
  3. Install dependencies (including rcmdcheck)
  4. Run `R CMD check`
  5. Display testthat output
  6. Upload check results on failure

### Building the Package

**ALWAYS use these commands in the order shown:**

1. **Clean build artifacts** (if previous build exists):
   ```bash
   rm -rf ..Rcheck/ *.tar.gz
   ```

2. **Install dependencies** (if needed):
   ```R
   # From within R console
   install.packages(c("devtools", "testthat", "rcmdcheck"))
   ```

3. **Load package for development**:
   ```R
   devtools::load_all()
   ```

4. **Build package tarball**:
   ```bash
   R CMD build .
   ```
   - Creates `fganalysis_0.2.3.tar.gz` (version may vary)
   - Takes ~5-10 seconds

5. **Check package** (full validation):
   ```bash
   R CMD check fganalysis_0.2.3.tar.gz --no-manual --no-vignettes
   ```
   - Takes ~30-60 seconds
   - Creates `..Rcheck/` directory with results
   - Check log: `..Rcheck/00check.log`
   - **Expected output**: May show 1 WARNING about `..Rcheck` directory and 4 NOTEs (these are normal)

### Running Tests

**ALWAYS run tests using one of these methods:**

1. **Using devtools** (recommended during development):
   ```R
   devtools::test()
   ```
   - Runs all tests in `tests/testthat/`
   - Takes ~5-15 seconds
   - Shows detailed test output

2. **Using R CMD check** (CI equivalent):
   ```bash
   R CMD check fganalysis_0.2.3.tar.gz
   ```
   - Includes tests as part of full package check
   - See test output in `..Rcheck/tests/testthat.Rout`

3. **Using testthat directly**:
   ```R
   library(testthat)
   library(fganalysis)
   test_check("fganalysis")
   ```

### Linting

**Run linter before committing:**
```R
library(lintr)
lint_package()
```
- Configuration in `.lintr`: 4-space indentation, no line length limit
- Should show no errors for compliant code

## Common Build Issues & Workarounds

### Issue: Global variable warnings in R CMD check
**Symptom**: NOTEs about "no visible binding for global variable"
**Cause**: Using dplyr/tidyverse NSE (non-standard evaluation)
**Fix**: Add to file with issue:
```R
utils::globalVariables(c("VARIABLE_NAME_1", "VARIABLE_NAME_2"))
```

### Issue: DuckDB version conflicts (Sandbox environment)
**Symptom**: Package loading errors with duckdb
**Workaround documented in README**:
```R
# Install older compatible versions first
install.packages("/usr/finngen-repos/cran/source/src/contrib/duckdb_1.2.1.tar.gz")
install.packages("/usr/finngen-repos/cran/source/src/contrib/duckdbfs_0.1.0.tar.gz")
```

### Issue: Hidden files warning in R CMD check
**Symptom**: NOTE about `.gitignore`, `.lintr`, `.github`, `.git` being included
**Status**: Expected behavior - these are listed in `.Rbuildignore`
**Action**: Ignore this NOTE

### Issue: LazyData without data directory
**Symptom**: NOTE "LazyData is specified without a 'data' directory"
**Status**: Expected - package doesn't include data, only data access functions
**Action**: Ignore this NOTE

## Key Development Patterns

### Function Documentation
- **ALWAYS use roxygen2** format for function documentation
- Include `@title`, `@description`, `@param`, `@return`, `@export`
- Run `devtools::document()` to regenerate `man/` and `NAMESPACE`

### Code Style
- **Indentation**: 4 spaces (enforced by `.lintr`)
- **Line length**: No limit (disabled in linter config)
- **Naming**: snake_case for functions, PascalCase for S3 classes
- **Comments**: Minimal - only for complex logic or explanations

### Testing Pattern
All test files follow this structure:
```R
library(testthat)
library(dplyr)  # if needed

test_that("descriptive test name", {
  # Setup test data
  # Call function
  # Assertions with expect_*
})
```

### Data Access Pattern
The package uses lazy evaluation with dplyr:
1. Create connection: `conn <- connect_fgdata("config/db_config.json")`
2. Build query: `data <- conn$labs %>% filter(...) %>% select(...)`
3. Execute query: `result <- collect(data)`

### S3 Class Pattern
- Main class: `drug.response` (see `drug_response_core.R`)
- Constructor: `drug.response(responses, lab_measurements, drug_purchases, before_period, after_period)`
- Print method: `print.fg_data_connection()`

## Validation Checklist

Before finalizing changes:

1. **Lint**: Run `lintr::lint_package()` - should show no new errors
2. **Test**: Run `devtools::test()` - all tests should pass
3. **Build**: Run `R CMD build .` - should complete without errors
4. **Check**: Run `R CMD check *.tar.gz` - should show only expected NOTEs/WARNINGs
5. **Documentation**: If you changed exported functions, run `devtools::document()`

## Critical Notes

- **DO NOT** commit `.Rcheck/` directory - it's a build artifact
- **DO NOT** commit local config files - they're in `.gitignore`
- **DO NOT** commit PDF outputs or temporary test files
- **DO NOT** modify `NAMESPACE` manually - it's generated by roxygen2
- **DO** run `devtools::document()` after changing roxygen comments
- **DO** add tests for new exported functions
- **DO** update README.md if adding significant new functionality
- **TRUST** these instructions - they are validated and comprehensive

## Quick Reference

```bash
# Full validation workflow (run in repository root)
rm -rf ..Rcheck/ *.tar.gz                          # Clean
R CMD build .                                       # Build (~10s)
R CMD check fganalysis_*.tar.gz --no-manual --no-vignettes  # Check (~60s)

# Development workflow (from R console)
devtools::load_all()      # Load package for testing
devtools::test()          # Run tests (~15s)
devtools::document()      # Regenerate documentation
lintr::lint_package()     # Check code style
```

**Package file count**: 6 R source files, 4 test files, 3 scripts, 2 config files, ~30 man pages
