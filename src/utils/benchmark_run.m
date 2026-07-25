function elapsed = benchmark_run(run_id)
%BENCHMARK_RUN  Time a single model run.
%
%   elapsed = benchmark_run(run_id)
%
% Runs MODEL_FORECAST_RUN once and reports the wall-clock time in seconds.
% Useful for profiling and for choosing the ensemble size / worker count in
% RUN_PIPELINE.
%
% Note the timing includes writing the (large) output file. Comment out the
% final save in MODEL_FORECAST_RUN to time the computation alone.
%
% (Formerly Test_runtime.m, which still called the pre-rename MODEL_RUN.)

setup_paths();

mmdd = datestr(datetime('now'), 'mmdd');   %#ok<DATST>

start_time = datetime('now');
model_forecast_run(run_id, mmdd);
elapsed = seconds(datetime('now') - start_time);

fprintf('Runtime for run %d: %.1f seconds\n', run_id, elapsed);

end
