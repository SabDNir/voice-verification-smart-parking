function mode = digitVoiceNoiseMode(cfg)
%DIGITVOICENOISEMODE Calibration must match the runtime processing.
if nargin < 1 || isempty(cfg), cfg = vsConfig(); end
if ~cfg.SpectralSubtraction
    mode = 'off';
elseif isfield(cfg,'AmbientNoiseProfile') && ~isempty(cfg.AmbientNoiseProfile)
    mode = 'shared';
else
    mode = 'quiet';
end
end
