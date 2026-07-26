function make_forecast_metrics_real()
%MAKE_FORECAST_METRICS_REAL  Forecast metrics for the real-incidence runs.
%
%   make_forecast_metrics_real()
%
% Same as MAKE_FORECAST_METRICS but for runs driven by reported COVID-19
% incidence (run IDs 601-604). Metrics are computed per epidemic wave
% ("slice") defined in data/truths/real_stats.mat, and written as
% *_fore_real_stats.mat to results/forecasts/.
%
% See also MAKE_FORECAST_METRICS, CALCULATE_FORECAST_METRICS.

paths = setup_paths();

population = load_var(paths.population, 'population');
real_stats = load_var(paths.real_stats, 'real_stats');

file_list = dir(fullfile(paths.model_runs, '*_real_*.mat'));
fprintf('Found %d real-incidence run(s) in %s\n', numel(file_list), paths.model_runs);

% Define onset thresholds to calculate metrics for
onset_thresholds = [25, 50, 100, 200, 300];
%define the name of the peak variables
peak_targets = ["peak_week", "peak_inci"];


%% LOOP OVER FILES
for f_idx = 1:length(file_list)
    current_file_path = fullfile(file_list(f_idx).folder, file_list(f_idx).name);
    current_file_name = file_list(f_idx).name;

    fprintf('Processing: %s\n', current_file_name);
    load(current_file_path, 'forecast_struct');

    for t=1:length(forecast_struct)

        forecast_struct(t).forecast_week_abs = forecast_struct(t).week_counter + 1;
        % Sanity check
        expected_week = (forecast_struct(t).start_day / 7) + 1;
        if forecast_struct(t).forecast_week_abs ~= expected_week
            warning('Mismatch at t=%d: week_counter+1=%d, start_day/7+1=%d', ...
                t, forecast_struct(t).forecast_week_abs, expected_week);
        end

        % Sum cases for each week + convert to rate over 100K
        num_times = size(forecast_struct(t).dailyIr, 2);
        num_weeks = floor(num_times / 7);
        for week = 1:num_weeks
            start_day = (week - 1) * 7 + 1;
            end_day = week * 7;
            forecast_struct(t).dailyIr_100K_week(:,week,:) = single(sum(forecast_struct(t).dailyIr(:, start_day:end_day,:), 2)./ population * 100000);
        end
        % Initialize slices struct to avoid overwriting
        forecast_struct(t).slices = struct();


        % Loop over slices
        for slice_idx=1:length(real_stats.slice_names)
            slice_name = real_stats.slice_names(slice_idx);
            start_week = real_stats.(slice_name).start_week;
            end_week = real_stats.(slice_name).end_week;

            % SLICE THE FORECAST DATA
            slice_data = forecast_struct(t).dailyIr_100K_week(:, start_week:end_week, :);
            num_locations = size(slice_data, 1);

            %% onset tresholds loop
            for wn_idx = 1:length(onset_thresholds)
                wn = onset_thresholds(wn_idx);
                field_name = sprintf('onset%d', wn);
                truth_field = sprintf('onset%d', wn);

                % Calculate onset weeks for this slice
                [~, onset_week] = max(slice_data >= wn, [], 2);
                onset_week(~any(slice_data >= wn, 2)) = NaN;

                % Store raw values in slice struct
                forecast_struct(t).slices.(slice_name).(field_name) = single(squeeze(onset_week));

                % set onset truth and forecast
                truth_onset = real_stats.(slice_name).(truth_field);
                % zero means "at cutoff day" so add NaN to not consider them
                truth_onset(truth_onset == 0) = NaN;

                forecast_ensemble = forecast_struct(t).slices.(slice_name).(field_name);

                metrics_template = calculate_forecast_metrics([], NaN);
                metrics_array = repmat(metrics_template, num_locations, 1);

                for loc = 1:num_locations
                    truth_value = truth_onset(loc);
                    truth_value = truth_value-start_week+1; % this aligns the truth value(abs week number) to the forecast (starts form start_week)
                    forecast_values = forecast_ensemble(loc, :);
                    metrics_array(loc) = calculate_forecast_metrics(forecast_values, truth_value);
                end

                forecast_struct(t).slices.(slice_name).([field_name '_metrics']) = metrics_array;
            end

            %% peak week and peak inci loop
            % Calculate peak for this slice
            [peak_inci, peak_week_rel] = max(slice_data, [], 2);

            % Store raw values
            forecast_struct(t).slices.(slice_name).peak_inci = single(squeeze(peak_inci));
            % Note: this is relative to slice start.
            forecast_struct(t).slices.(slice_name).peak_week = int8(squeeze(peak_week_rel));

            for p_idx = 1:length(peak_targets)
                field_name = peak_targets(p_idx);
                truth_field = field_name;

                if truth_field == "peak_week"
                    truth_field = "peak_week_abs";
                    % If comparing to absolute truth, adjust forecast peak to absolute
                    forecast_ensemble = single(forecast_struct(t).slices.(slice_name).peak_week) + start_week - 1;
                else
                    forecast_ensemble = forecast_struct(t).slices.(slice_name).(field_name);
                end

                truth_values = real_stats.(slice_name).(truth_field);

                metrics_template = calculate_forecast_metrics([], NaN);
                metrics_array = repmat(metrics_template, num_locations, 1);

                for loc = 1:num_locations
                    truth_value = truth_values(loc);
                    forecast_values = forecast_ensemble(loc, :);
                    metrics_array(loc) = calculate_forecast_metrics(forecast_values, truth_value);
                end

                metrics_field_name = sprintf('%s_metrics', field_name);
                forecast_struct(t).slices.(slice_name).(metrics_field_name) = metrics_array;
            end
        end
    end

    % Save Output
    forecast_file_name_path = fullfile(paths.forecasts, ...
        replace(current_file_name, ".mat", "_fore_real_stats.mat"));

    fprintf('saving %s \n\n', forecast_file_name_path);
    save(forecast_file_name_path, "forecast_struct", "-v7.3");
end

end
