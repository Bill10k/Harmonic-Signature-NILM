function [frequency, magnitude] = computeFFT(signal, Fs)

N = length(signal);

X = fft(signal);

magnitude = abs(X)/N;

frequency = (0:N-1)*(Fs/N);

half = floor(N/2);

frequency = frequency(1:half);

magnitude = magnitude(1:half);

end