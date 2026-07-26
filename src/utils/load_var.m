function value = load_var(filename, varname)
%LOAD_VAR  Load one named variable from a .mat file.
%
%   value = load_var(filename, varname)
%
% Preferred over a bare `load(filename)` inside a function: the variable is
% assigned explicitly, so MATLAB (and the reader) can see where it comes from.
% This also matters for PARFOR, which has to resolve every variable it
% broadcasts at compile time and cannot do that for names conjured by `load`.

s = load(filename, varname);
if ~isfield(s, varname)
    error('load_var:missingVariable', ...
        'Variable "%s" not found in %s', varname, filename);
end
value = s.(varname);

end
