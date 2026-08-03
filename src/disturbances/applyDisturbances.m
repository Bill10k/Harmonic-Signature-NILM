function [disturbedSignal, disturbanceInfo] = applyDisturbances(signal, params)
%APPLYDISTURBANCES Applies all supply disturbance models in sequence.
%
%   [disturbedSignal, disturbanceInfo] = APPLYDISTURBANCES(signal, params)
%
%   The order of the four stages is not arbitrary - it follows the physical
%   path from the feeder to the meter:
%
%     1. applyVoltageSag        feeder voltage dips, so load current falls
%     2. addHarmonicDistortion  other customers inject background harmonics
%     3. applyInterruption      a recloser opens and recloses
%     4. addGaussianNoise       the meter's own measurement noise
%
%   Noise is added last because it belongs to the instrument, which sits at
%   the end of the path. Everything before it happens on the network.
%
%   INPUTS
%     signal : column vector, clean aggregate current in amperes
%     params : project parameter struct (see defaultParameters.m)
%
%   OUTPUTS
%     disturbedSignal : column vector, current after all disturbances
%     disturbanceInfo : struct with one field per stage, each describing
%                       exactly what was applied. This is what the report
%                       quotes, so the numbers in the document always match
%                       the numbers in the run.

    signal = signal(:);

    disturbedSignal = signal;

    disturbanceInfo = struct();
    disturbanceInfo.inputRMS_A = sqrt(mean(signal.^2));

    % 1. Voltage sag ------------------------------------------------------
    [disturbedSignal, disturbanceInfo.sag] = applyVoltageSag(disturbedSignal, params);

    % 2. Background harmonic distortion from the rest of the feeder --------
    [disturbedSignal, disturbanceInfo.distortion] = addHarmonicDistortion(disturbedSignal, params);

    % 3. Supply interruption and recovery ---------------------------------
    [disturbedSignal, disturbanceInfo.interruption] = applyInterruption(disturbedSignal, params);

    % 4. Measurement noise ------------------------------------------------
    [disturbedSignal, disturbanceInfo.noise] = addGaussianNoise(disturbedSignal, params);

    % Summary -------------------------------------------------------------
    disturbanceInfo.outputRMS_A = sqrt(mean(disturbedSignal.^2));

    if disturbanceInfo.inputRMS_A > 0
        disturbanceInfo.rmsChange_percent = ...
            100 * (disturbanceInfo.outputRMS_A - disturbanceInfo.inputRMS_A) / disturbanceInfo.inputRMS_A;
    else
        disturbanceInfo.rmsChange_percent = 0;
    end

    disturbanceInfo.stageOrder = {'voltage sag', 'background harmonic distortion', ...
                                  'supply interruption', 'measurement noise'};

end
