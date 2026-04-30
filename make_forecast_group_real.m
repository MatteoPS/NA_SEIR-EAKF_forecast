% Aggregates real data forecast metrics across all countries and waves.
% Output structure: all_real_data.(Settings).(Target).(BinName)

% 1. Setup
sc          = load('statecodes.mat');
statecodes  = sc.statecodes;
%load population.mat
truth       = load('Truths/1211_real_stats.mat');
real_stats  = truth.real_stats;

run_ids = 601:604;
loc_countries = statecodes.Var3;

output_dir = 'Forecasts_groups';
if ~exist(output_dir, 'dir'), mkdir(output_dir); end

summary_filename = fullfile(output_dir, sprintf('%s_all_real_forecast_metrics.mat', datestr(now, 'mmdd')));
fprintf('Output file: %s\n\n', summary_filename);

% Define targets and metrics
all_targets = ["onset50", "onset100"];
metrics_to_collect = ["wis", "mae"];
coverage_to_collect = ["interval_90", "interval_50"];
all_metrics = [metrics_to_collect, coverage_to_collect];

% 2. Find Real Forecast Files
file_list = [];
for i = 1:length(run_ids)
    files_found = dir(sprintf('Forecasts/*_%d_*_fore_real_stats.mat', run_ids(i)));
    file_list = [file_list; files_found];
end

all_real_data = struct();

%% 3. Main Loop over Files (Models)
for f_idx = 1:length(file_list)
    current_file_path = fullfile(file_list(f_idx).folder, file_list(f_idx).name);
    fprintf('Processing file: %s\n', file_list(f_idx).name);

    forecast_struct = load(current_file_path, 'forecast_struct').forecast_struct;
    settings = string(extractBetween(file_list(f_idx).name, 'real_', '_fore'));

    % bins.(Target).(BinName).(Metric) = [values...]
    bins = struct();

    %% 4. Loop over Forecast Weeks
    for t = 1:length(forecast_struct)
        if isempty(forecast_struct(t).slices), continue; end
        if ~isfield(forecast_struct(t), 'forecast_week_abs')
            warning('Missing forecast_week_abs for t=%d in file %s', t, file_list(f_idx).name);
            continue;
        end
        forecast_week_abs = forecast_struct(t).forecast_week_abs;

        %% 5. Loop over Slices
        for s_idx = 1:length(fieldnames(forecast_struct(t).slices))
            available_slices = fieldnames(forecast_struct(t).slices);
            slice_name = available_slices{s_idx};
            slice_data = forecast_struct(t).slices.(slice_name);

            %% 6. Loop over Targets
            for target_idx = 1:length(all_targets)
                target_name = all_targets(target_idx);
                metrics_field = sprintf('%s_metrics', target_name);
                if ~isfield(slice_data, metrics_field), continue; end

                metrics_struct = slice_data.(metrics_field);

                %% 7. Loop over Locations
                for loc = 1:length(metrics_struct)

                    true_week_abs = get_true_event_week(real_stats, slice_name, target_name, loc);
                    if isnan(true_week_abs) || true_week_abs == 0, continue; end

                    % Compute time bin relative to event
                    weeks_to_event = forecast_week_abs - true_week_abs;
                    if weeks_to_event >= 0
                        bin_name = sprintf('week_p%d', weeks_to_event);
                    else
                        bin_name = sprintf('week_m%d', abs(weeks_to_event));
                    end

                    % Collect standard metrics
                    for m_idx = 1:length(metrics_to_collect)
                        m_name = metrics_to_collect(m_idx);
                        if isfield(metrics_struct(loc), m_name)
                            val = metrics_struct(loc).(m_name);
                            if ~isnan(val)
                                bins = bin_value(bins, target_name, bin_name, m_name, val);
                            end
                        end
                    end

                    % Collect coverage metrics
                    for c_idx = 1:length(coverage_to_collect)
                        m_name = coverage_to_collect(c_idx);
                        if isfield(metrics_struct(loc), 'coverage') && ...
                                isfield(metrics_struct(loc).coverage, m_name)
                            val = metrics_struct(loc).coverage.(m_name);
                            bins = bin_value(bins, target_name, bin_name, m_name, val);
                        end
                    end

                end % loc
            end % target
        end % slice
    end % t

    %% 8. Aggregate and Store
    all_real_data.(settings) = aggregate_bins(bins, all_targets, all_metrics);

end

% Save
fprintf('\nSaving to %s\n', summary_filename);
save(summary_filename, '-struct', 'all_real_data', '-v7.3');
fprintf('Done.\n');


%% --- HELPER FUNCTIONS ---

    function true_week_abs = get_true_event_week(real_stats, slice_name, target_name, loc)
        true_week_abs = NaN;
        if ~isfield(real_stats, slice_name), return; end

        truth_slice = real_stats.(slice_name);
        truth_field = '';

        if startsWith(target_name, "peak")
            if isfield(truth_slice, 'peak_week_abs')
                truth_field = 'peak_week_abs';
            elseif isfield(truth_slice, 'peak_week')
                truth_field = 'peak_week';
            end
        elseif startsWith(target_name, "onset")
            truth_field = target_name;
        end

        if ~isempty(truth_field) && isfield(truth_slice, truth_field)
            val = truth_slice.(truth_field);
            if loc <= length(val)
                true_week_abs = double(val(loc));
            end
        end
    end

    function bins = bin_value(bins, target_name, bin_name, m_name, val)
        if ~isfield(bins, target_name),                        bins.(target_name) = struct();             end
        if ~isfield(bins.(target_name), bin_name),             bins.(target_name).(bin_name) = struct();  end
        if ~isfield(bins.(target_name).(bin_name), m_name),    bins.(target_name).(bin_name).(m_name) = []; end

        bins.(target_name).(bin_name).(m_name)(end+1) = val;
    end

    function summary = aggregate_bins(bins, all_targets, all_metrics)
        summary = struct();
        if isempty(fieldnames(bins)), return; end

        for target_name_cell = all_targets
            target = target_name_cell{:};
            if ~isfield(bins, target), continue; end

            for w_i = 1:length(fieldnames(bins.(target)))
                weeks = fieldnames(bins.(target));
                bin_name = weeks{w_i};

                for m_name_cell = all_metrics
                    m_name = m_name_cell{:};
                    if ~isfield(bins.(target).(bin_name), m_name), continue; end

                    vals = bins.(target).(bin_name).(m_name);
                    if isempty(vals), continue; end

                    summary.(target).(bin_name).(strcat('mean_', m_name))   = mean(vals, 'omitnan');
                    summary.(target).(bin_name).(strcat('median_', m_name)) = median(vals, 'omitnan');
                    summary.(target).(bin_name).num_samples                 = length(vals);
                end
            end
        end
    end
