function disturbedSignal = applyDisturbances(signal, params)
%APPLYDISTURBANCES Applies all disturbance models in sequence.

    disturbedSignal = signal;

    disturbedSignal = applyVoltageSag(disturbedSignal, params);
    disturbedSignal = addHarmonicDistortion(disturbedSignal, params);
    disturbedSignal = applyInterruption(disturbedSignal, params);
    disturbedSignal = addGaussianNoise(disturbedSignal, params);
end