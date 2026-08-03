function value = load_var(filename, varname)
%LOAD_VAR  Load one named variable from a .mat file.
%
%   value = load_var(filename, varname)
%
% Assigning explicitly, rather than letting a bare `load(filename)` inject
% names into the workspace, keeps it clear where a variable comes from. PARFOR
% requires it: it resolves the variables it broadcasts at compile time, and
% cannot see names that only appear at run time.

s = load(filename, varname);
if ~isfield(s, varname)
    error('load_var:missingVariable', ...
        'Variable "%s" not found in %s', varname, filename);
end
value = s.(varname);

end
