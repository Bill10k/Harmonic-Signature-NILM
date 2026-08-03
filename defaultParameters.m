function params = defaultParameters()
%DEFAULTPARAMETERS Single source of truth for every setting in the project.
%
%   params = DEFAULTPARAMETERS()
%
%   Every number the pipeline uses lives here, with the reason for its value
%   written beside it. Nothing downstream invents a constant of its own, so
%   the report and the code can never drift apart.
%
%   Our group was not issued a parameter sheet, so each value below is a
%   design decision we have to defend. The justification is given inline.

params = struct();

%% ========================================================================
%  SAMPLING
%  ========================================================================

% Sampling frequency, Hz.
%   The highest harmonic we model is the 15th at 15 x 50 = 750 Hz. Nyquist
%   therefore demands more than 1500 Hz. We use 4000 Hz, which is 5.3 times
%   the highest frequency of interest. The headroom is not waste: it leaves
%   room for a realistic anti-aliasing filter to roll off between 750 Hz and
%   2000 Hz instead of requiring a brick wall, and it keeps 4000 Hz within
%   what an inexpensive metering ADC can sustain continuously.
params.fs = 4000;

% Fundamental supply frequency, Hz. 50 Hz is the Ghanaian standard.
params.f0 = 50;

% Length of the simulated recording, seconds.
params.duration = 12;

%% ========================================================================
%  ANALYSIS WINDOW
%  ========================================================================

% Window length, seconds.
%   0.20 s at 50 Hz is exactly TEN fundamental cycles. A whole number of
%   cycles makes the analysis coherent: every harmonic lands precisely on an
%   FFT bin centre, so there is no leakage between harmonics and each
%   amplitude can be read straight from its bin. At 4000 Hz the window holds
%   800 samples and the bin spacing is 4000/800 = 5 Hz, so 50, 150, 250 Hz
%   and so on all fall exactly on bins.
%
%   The trade-off: a longer window resolves frequency more finely but blurs
%   the moment an appliance switches. 0.2 s keeps switching events localised
%   to within a fifth of a second, which is far finer than the seconds-long
%   appliance cycles we need to track.
params.windowLength = 0.20;

% Hop between consecutive windows, seconds.
%   0.10 s is five fundamental cycles, so consecutive windows are also a
%   whole number of cycles apart and their harmonic phases stay directly
%   comparable. It gives 50% overlap, so no switching event can fall in a
%   blind spot between windows.
params.hopLength = 0.10;

% Window shape. Options: 'hann', 'hamming', 'blackman', 'rectangular'.
%   Hann is chosen over Hamming for the analysis window. Hamming has a lower
%   first sidelobe (-43 dB against -31 dB) but its sidelobes fall away slowly,
%   at 6 dB per octave. Hann's fall at 18 dB per octave, so distant strong
%   harmonics leak far less into the weak ones - and separating the 0.7 A LED
%   bank's harmonics from the 6 A kettle's fundamental is exactly a
%   far-from-strong-signal problem.
params.windowType = 'hann';

%% ========================================================================
%  HARMONICS OF INTEREST
%  ========================================================================

% Only ODD harmonics are analysed. A symmetric load with half-wave symmetry
% produces no even harmonics, so reading them would add noise and no signal.
params.analysisHarmonics = [1 3 5 7 9 11 13 15];

% Highest harmonic the FIR filter must preserve.
params.maxHarmonic = 15;

%% ========================================================================
%  FIR FILTER
%  ========================================================================

% Transition-band margin above the highest harmonic of interest, Hz.
%   The passband must reach 750 Hz. The cutoff is placed at
%   750 + 25 = 775 Hz so that the 15th harmonic sits inside the passband
%   rather than on the shoulder where it would be attenuated.
params.cutoffMarginHz = 25;

% Window used to design the FIR kernel.
%   Hamming is the standard choice for the window method: it gives about
%   53 dB of stopband attenuation, which is more than enough to suppress
%   out-of-band noise without needing the very long kernel that Blackman's
%   74 dB would demand.
params.filterWindowType = 'hamming';

%% ========================================================================
%  SUPPLY DISTURBANCES
%
%  No disturbance profile was assigned to our group, so these values are
%  anchored to published standards rather than chosen for convenience.
%  ========================================================================

% --- Voltage sag -------------------------------------------------------
% IEEE Std 1159 defines a sag as 0.1 to 0.9 pu lasting 0.5 cycles to 1
% minute. A 30% drop for 0.30 s is 15 cycles, which IEEE 1159 classifies as
% an INSTANTANEOUS sag - the most common category on a distribution feeder,
% typically caused by a remote fault being cleared.
params.applySag = true;
params.sagDepth = 0.30;
params.sagStartTime = 4.00;
params.sagDuration = 0.30;
params.sagTransition = 1/50;

% --- Background harmonic distortion ------------------------------------
% IEEE Std 519 recommends a voltage THD limit of 5% below 69 kV. A feeder
% described as unstable is one where that limit is NOT met, so 8% is used:
% deliberately non-compliant, and deliberately injected at the 5th, 7th and
% 11th - orders our own appliances also use, which is the hardest case.
params.applyDistortion = true;
params.supplyTHD = 0.08;
params.distortionOrders = [5 7 11];
params.distortionWeights = [1 0.6 0.35];
params.distortionPhases = [25 -60 140];

% --- Supply interruption -----------------------------------------------
% IEEE Std 1159 defines an interruption as below 0.1 pu. 0.10 s is 5 cycles,
% which is characteristic of an auto-recloser clearing a transient fault.
params.applyInterruptionStage = true;
params.interruptionStartTime = 7.50;
params.interruptionDuration = 0.10;
params.interruptionResidual = 0.02;
params.interruptionCollapseTau = 0.002;
params.interruptionRecoveryTau = 0.05;

% --- Measurement noise --------------------------------------------------
% 35 dB SNR represents a low-cost current transformer front end. This is
% pessimistic on purpose: it puts the LED bank's higher harmonics close to
% the noise floor, which is where the interesting failures appear.
params.applyNoise = true;
params.noiseSNR_dB = 35;

% Fixed seed so every run reproduces exactly. The course team must be able
% to re-run our analysis and obtain our numbers.
params.randomSeed = 20897245;

%% ========================================================================
%  FEATURE EXTRACTION
%  ========================================================================

% A window whose fundamental falls below this is treated as a dead supply
% rather than as a set of switched-off appliances. Set just above the noise
% floor implied by the SNR above.
params.fundamentalFloor_A = 0.05;

%% ========================================================================
%  CLASSIFIER
%  ========================================================================

% Three classifiers are implemented so the report can compare them:
%
%   'nnls'        solves for a non-negative coefficient per appliance -
%                 how much of each one is present - and declares an
%                 appliance ON when its coefficient passes onThreshold.
%                 This is the default.
%
%   'combination' tests all 16 all-or-nothing on/off combinations and keeps
%                 the best fit. Equal to 'nnls' on our own data but markedly
%                 less robust to unseen devices, because a single common
%                 gain cannot absorb per-appliance amplitude variation.
%
%   'rules'       fixed thresholds applied to each appliance independently.
%                 The conventional approach, kept to demonstrate why it
%                 fails on an aggregate measurement.
%
% On twelve held-out traces with appliance parameters perturbed by up to 15%
% in current and 20% in harmonic ratios, plus harsher disturbances:
%   nnls        mean macro-F1 0.975, worst 0.940
%   combination mean macro-F1 0.864, worst 0.682
params.classifierMethod = 'nnls';

% An appliance is declared ON when its estimated coefficient reaches this
% fraction of nominal. A genuinely running appliance produces a coefficient
% near 1.0; a spurious one, absorbing residual error, sits near 0.5.
%
% Selected by sweeping on held-out traces, WITH background subtraction on:
%     0.45 -> macro-F1 0.951      0.55 -> macro-F1 0.971
%     0.50 -> macro-F1 0.955      0.60 -> macro-F1 0.962
%
% We disclose that this is a tuned value. It was tuned on traces we
% generated ourselves, never on any released benchmark data.
params.onThreshold = 0.55;

% Estimate the feeder's own background harmonic distortion and subtract it
% before classifying. Two passes: classify, take the median unexplained
% residual across live windows as the background, subtract, classify again.
%
% Without this, harmonics injected by OTHER customers on the feeder are
% credited to whichever of our appliances has a matching shape. We measured
% this on a held-out recording: a window containing only the kettle showed
% 11.9% THD, with the 5th, 7th and 11th harmonics in the ratio 1 : 0.64 :
% 0.35 - the injected background almost exactly - and the laptop charger was
% reported as running. Its precision fell to 0.73.
%
% Effect on held-out traces at 12% background THD:
%     off  macro-F1 0.934, worst case 0.671
%     on   macro-F1 0.971, worst case 0.930
% At 0% background THD the difference is nil, so it costs nothing on a
% clean feeder.
params.estimateBackground = true;

% A voltage sag scales every appliance current down together, so the matcher
% is allowed to fit a common gain in this range before judging the fit.
%
% The band is deliberately ASYMMETRIC, and this is worth understanding
% because a symmetric band measurably damages the result.
%
%   Downward to 0.5: a sag reduces current, and IEEE 1159 allows a sag as
%   deep as 0.1 pu. Allowing the gain to fall to 0.5 covers every sag we are
%   likely to meet; anything deeper collapses the fundamental far enough for
%   the not-live test to take over instead.
%
%   Upward only to 1.10: almost nothing legitimately makes the measured
%   current LARGER than the sum of the templates. Allowing much more lets
%   the matcher drop a genuine appliance and stretch the remaining templates
%   to cover the gap. We measured exactly that: with the band set to
%   [0.6, 1.4] the matcher discarded the 2 A refrigerator whenever the 6 A
%   kettle was also running, because a gain of 1.26 on the survivors
%   explained the total nearly as well. Refrigerator F1 was 0.891.
%   Tightening the upper bound to 1.10 raised it to 0.993 and lifted overall
%   accuracy from 94.96% to 97.90%.
params.gainMin = 0.50;
params.gainMax = 1.10;

% How much the fundamental and the harmonic fingerprint each count. Equal
% weighting stops the kettle's large fundamental from drowning out the
% harmonic detail that identifies the small loads.
params.weightFundamental = 0.5;
params.weightHarmonics = 0.5;

% Hold the previous decision through a supply outage instead of reporting
% every appliance as switched off. No current does not mean no load.
params.holdThroughOutage = true;

% ...but only for so long. A window with no current means either the supply
% was interrupted (hold, the appliances are still on) or nothing is running
% (report everything off). Current alone cannot tell these apart, so we use
% duration: IEEE 1159 places the boundary between an instantaneous and a
% momentary event at 30 cycles, which is 0.6 s, which at our 0.1 s hop is
% six windows. Silence lasting longer is better explained by an idle house
% than by an outage.
%
% This was found by testing on held-out data, not on our own recording.
% Without the cap, a long idle stretch was treated as one long outage and
% the appliances last seen were reported throughout it - 31 false positives
% on the laptop charger in one held-out trace, precision 0.73.
params.maxHoldWindows = 6;

% Majority vote across this many consecutive windows. Appliances run for
% seconds; windows advance every 0.1 s, so an isolated one-window flip is
% almost certainly noise. Set to 1 to disable.
params.smoothWindows = 3;

% Residual floor used when normalising the match cost, amperes.
params.residualFloor_A = 0.05;

% Current change treated as a switching event, amperes.
params.eventThreshold_A = 0.25;

% Tolerance either side of each appliance's derived threshold, for the
% rule-based classifier only.
params.ruleTolerance = 0.5;

%% ========================================================================
%  OUTPUT
%  ========================================================================

params.plotResults = true;      % produce the report figures
params.saveFigures = true;      % write them to figures/
params.plotSpectrum = false;    % do NOT plot inside performFFT; one figure
                                % per window would open over a hundred windows
params.verbose = true;
params.figureDir = fullfile('figures', 'results');

end
