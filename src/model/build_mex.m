function build_mex()
%BUILD_MEX  Compile integrate_model.cpp for the current platform.
%
%   build_mex()
%
% Writes integrate_model.<mexext> next to the source in src/model/. Run this
% after editing integrate_model.cpp, or on a machine that has no pre-compiled
% binary for its architecture.
%
% Requires a C++ compiler set up for MEX (`mex -setup C++`).
%
% See also MODEL_FORECAST_RUN.

paths = setup_paths();
model_dir = fullfile(paths.root, 'src', 'model');
src = fullfile(model_dir, 'integrate_model.cpp');

fprintf('Compiling %s\n', src);

% -R2017b selects the classic C MEX interface (mexFunction + mxGetPr), which
% is what integrate_model.cpp is written against.
%
% LINKEXPORTCPP= blanks the flags that force-link the matlab::mex::Function
% adapter symbols. This file does not use that API, and on recent macOS
% linkers those flags turn into hard "undefined symbol" errors. Not every
% platform needs the override, so fall back to a plain build if it is
% rejected.
try
    mex('-R2017b', 'LINKEXPORTCPP=', src, '-outdir', model_dir);
catch err
    fprintf('Build with LINKEXPORTCPP override failed (%s); retrying without it.\n', ...
        err.identifier);
    mex('-R2017b', src, '-outdir', model_dir);
end

fprintf('Built %s\n', fullfile(model_dir, ['integrate_model.' mexext]));

end
