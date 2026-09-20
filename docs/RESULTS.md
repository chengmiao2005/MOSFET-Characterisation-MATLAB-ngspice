# Results and evidence

These results use a known educational MOSFET model. All recorded data are synthetic or simulated; fitting and held-out samples come from the same model.

## Model and extraction method

The channel model uses threshold voltage Vth, current-scale coefficient β and channel-length-modulation coefficient λ. β is not transconductance gm.

For positive overdrive, the saturation expression is:

$$I_D = \frac{\beta}{2}(V_{GS}-V_{th})^2(1+\lambda V_{DS}), \qquad V_{DS}\ge V_{GS}-V_{th}.$$

In the triode region:

$$I_D = \beta\left[(V_{GS}-V_{th})V_{DS}-\frac{V_{DS}^2}{2}\right](1+\lambda V_{DS}).$$

The model sets channel current to zero below threshold. It does not model subthreshold conduction, temperature dependence, self-heating or advanced short-channel effects.

At fixed VDS, a saturation-region linear fit of √ID against VGS supplies the threshold intercept and β(1 + λVDS). A separate saturation output fit at fixed VGS has slope/intercept ratio λ. Combining both fits then gives β. The fitting windows are selected using knowledge of this educational model.

## Stage 1 — synthetic readout errors

[Run directory](../evidence/stage1/20260920_154452/) · [Configuration](../evidence/stage1/20260920_154452/config.json) · [Scenario table](../evidence/stage1/20260920_154452/monte_carlo_SYNTHETIC.csv) · [Statistics](../evidence/stage1/20260920_154452/monte_carlo_summary_SYNTHETIC.csv)

All four methods use 400 paired scenarios. Gain and offset remain fixed within each scenario; noisy calibration readings are used to estimate a two-point correction. Reference currents and gate/drain voltages are assumed exact.

| Method | Threshold RMSE (mV) |
|---|---:|
| Single uncalibrated reading | 12.642821 |
| Mean of 25, uncalibrated | 12.543500 |
| Single calibrated reading | 1.723176 |
| Mean of 25, calibrated | 0.901146 |

Calibration plus averaging has the lowest aggregate RMSE for these assumptions. Nevertheless, **15/400 scenarios** have worse absolute threshold error after calibration than with uncalibrated averaging. No scenarios were discarded to improve this comparison. These statistics concern threshold extraction in this synthetic model, not uncertainty coverage or noisy extraction of all three parameters.

## Stage 2 — mechanisms and executed SPICE comparison

[Run directory](../evidence/stage2/20260920_165426/) · [Status](../evidence/stage2/20260920_165426/STATUS.txt) · [ngspice log](../evidence/stage2/20260920_165426/spice_case/ngspice_run.log) · [Comparison table](../evidence/stage2/20260920_165426/SPICE_comparison_summary.csv)

The error-mechanism study gives:

| Current input | Fitted Vth (V) |
|---|---:|
| Ideal channel current | 1.200000000 |
| Gain error only, +0.8% | 1.200000000 |
| Offset only, +15 µA | 1.183802020 |
| Gain and offset | 1.183930234 |
| Exact inverse correction using known coefficients | 1.200000000 |

Pure gain changes the square-root-fit slope but preserves its horizontal intercept in this particular model and method. This does not mean gain error is irrelevant to other extracted quantities. Exact correction here uses known coefficients with noise and quantisation disabled; it is a mathematical mechanism check, not evidence of perfect real-world calibration.

Applying the saturation method at VDS = 0.2 V to the same gate-voltage window produces an apparent threshold of approximately **0.472218 V**, even though the model threshold remains **1.2 V**. A good-looking fit is insufficient if the method's operating-region assumptions are violated.

The successful **ngspice 47** run contains two transfer sweeps of 176 points and six output sweeps of 121 points: **8 curves and 1,078 rows**. Every row satisfies the original tolerance:

$$|I_{SPICE}-I_{MATLAB}|\le 10^{-10}\ \mathrm{A}+10^{-6}|I_{MATLAB}|.$$

Maximum absolute difference: **3.010002837 × 10⁻¹² A**. The transfer residual is consistent with the netlist's junction/GMIN contribution, which is absent from the MATLAB channel-current-only expression. The tolerance was not relaxed.

## Stage 3 — extraction and held-out prediction

[Run directory](../evidence/stage3/20260920_172044/) · [Parameter table](../evidence/stage3/20260920_172044/parameters_MODEL_ONLY.csv) · [Prediction and split table](../evidence/stage3/20260920_172044/all_predictions_and_split.csv) · [Saved input hashes](../evidence/stage3/20260920_172044/input_snapshot/SHA256.json)

Stage 3 reuses the successful Stage 2 raw SPICE output; it does not run a new SPICE simulation.

| Parameter | Known model value | Extracted value |
|---|---:|---:|
| Vth (V) | 1.2 | 1.1999999967406676 |
| β (A/V²) | 0.002 | 0.0019999999898800904 |
| λ (V⁻¹) | 0.02 | 0.020000000591597466 |

The additional digits preserve the numerical result; they are not experimentally established significant figures.

| Partition | Count |
|---|---:|
| Raw rows from eight curves | 1,078 |
| Unique (VGS, VDS) combinations | 1,066 |
| Rows directly used in fits | 108 |
| Unique fitting combinations | 107 |
| All rows sharing fitting combinations, excluded from hold-out | 109 |
| Held-out rows before deduplication | 969 |
| Unique held-out combinations | 959 |

The partition groups coincident sweep intersections by voltage pair. No fitting bias occurs in the 959 unique held-out points. Their prediction residuals are:

- **RMSE:** 3.731914853 pA.
- **Maximum absolute error:** 11.622999438 pA.
- **Acceptance:** all points satisfy `1e-10 A + 1e-6 × abs(I_SPICE)`.

These residuals quantify same-model numerical prediction. They do not establish instrument accuracy or real-device generalisation.

### Parameter identifiability

[Candidate parameters](../evidence/stage3/20260920_172044/identifiability_candidates.csv) · [Transfer curves](../evidence/stage3/20260920_172044/identifiability_transfer_curves.csv) · [Output curves](../evidence/stage3/20260920_172044/identifiability_output_curves.csv)

Three candidate values of λ (0, 0.02 and 0.05 V⁻¹) are paired with β values that preserve β(1 + 3λ). The resulting fixed-VDS transfer curves coincide to numerical precision, while the output curves separate. Thus denser sampling of the same transfer curve does not separately identify β and λ; a second sweep supplies different information.

## Verification record

| Evidence | Result |
|---|---|
| Archived Stage 1 MATLAB self-checks | 12/12 |
| Archived Stage 2A MATLAB mechanism checks | 9/9 |
| Archived Stage 2B ngspice comparison | Executed; 1,078/1,078 rows within tolerance |
| Archived Stage 3 MATLAB self-checks | 13/13 |
| Python Stage 2 audit of this public dataset | 63/63 |
| Python Stage 3 audit of this public dataset | 21/21 |

Python reports are retained in [`verification/public_stage2/`](../verification/public_stage2/) and [`verification/public_stage3/`](../verification/public_stage3/). The Stage 3 audit verifies all 16 input-snapshot hashes, refits the parameters, reconstructs bias-point grouping and recomputes the held-out results. It also checks PNG decoding; that is not a visual-layout test.

An earlier archive review reported 23 Stage 3 checks because it also compared two historical ZIP archives. Those optional ZIP checks are outside the default public command. No fresh MATLAB or ngspice execution was performed while preparing this public repository.
