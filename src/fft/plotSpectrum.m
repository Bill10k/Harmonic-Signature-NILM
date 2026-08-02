function plotSpectrum(frequency, magnitude)

figure

plot(frequency, magnitude,'LineWidth',1.5)

grid on

xlabel('Frequency (Hz)')

ylabel('Magnitude')

title('Harmonic Spectrum')

xlim([0 500])

end