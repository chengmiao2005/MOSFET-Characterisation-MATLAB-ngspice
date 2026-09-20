# Public repository preparation

Prepared on 20 September 2026 from the completed three-stage project archive. This file records changes made for a portable public release.

## Preserved scientific records

- Archived CSV, DAT, MAT, PNG, configuration JSON and SPICE netlist files were copied byte-for-byte.
- Archived executed MATLAB source snapshots were preserved byte-for-byte.
- Numerical code, model parameters, fitting windows, data splits and acceptance tolerances were not changed.
- Both Stage 3 input snapshots and their existing `SHA256.json` files were preserved. Each manifest continues to match all 16 covered files.
- The three decoded MAT result structures were inspected for local filesystem paths; no private path strings were found.

## Restored runtime dependencies

The consolidated archive omitted reference CSV files required or used by the earlier stages. Exact original files were restored from their original project ZIPs; they were not regenerated:

| Public path | Original archive |
|---|---|
| `project/stage1/verification/ideal_reference_vectors.csv` | `PSI_MOSFET_Stage1_v1.zip` |
| `project/stage2/verification/mechanism_reference_MODEL.csv` | `PSI_Stage2B_StartHere.zip` |
| `project/stage2/verification/low_vds_fit_reference_MODEL.csv` | `PSI_Stage2B_StartHere.zip` |

Restoring the optional Stage 1 reference preserves its twelfth self-check. The Stage 2 launcher requires both restored reference files before starting.

## Comment-only source updates

Two comments in runnable copies were updated without changing executable MATLAB statements:

1. `project/stage1/PSI_MOSFET_Stage1.m`: the header now points to the repository's current documentation.
2. `project/stage3/RUN_STAGE3.m`: the stale “execution pending” header now points to the completed R2024a record.

The corresponding `evidence/.../executed_source.m` files retain their original historical comments. Archived evidence is authoritative for the exact executed source.

## Local-path redactions

Only local filesystem locations were redacted, with visible markers:

| File | Redaction |
|---|---|
| `evidence/stage1/20260920_154452/SUMMARY.txt` | Results folder replaced by `[REDACTED_LOCAL_RESULTS_PATH]` |
| `evidence/stage2/20260920_165426/spice_case/invocation.txt` | Executable and working-directory paths replaced by `[REDACTED_LOCAL_NGSPICE_PATH]` and `[REDACTED_LOCAL_WORKING_DIRECTORY]` |

The command flags and relative netlist/log filenames remain visible. These files are outside the unchanged Stage 3 hash manifests. Redaction does not affect numeric results or execution-status records.

## Documentation and verification

The public repository adds English/Chinese overviews, an exact result record, dependency installation instructions and ignored paths for future local outputs. It includes the original two Python audit scripts. Their optional historical ZIP checks remain available but are not needed for the default commands.

The two summary figures are copied unchanged from the existing archive. Their source CSVs are identified in `summary_figures/README.txt`; the stale reference to a missing regeneration script was removed. All original MATLAB figures remain under `evidence/`.

Fresh Python checks against the public tree passed **63/63 Stage 2 checks** and **21/21 Stage 3 checks**. Reports in `verification/public_stage2/` and `verification/public_stage3/` reflect the public files, including redacted log hashes. Local documentation links and scientific-file integrity were also checked. No new MATLAB or ngspice execution is claimed for this publication step.

