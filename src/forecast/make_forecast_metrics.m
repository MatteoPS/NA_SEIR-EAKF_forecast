function make_forecast_metrics()
%MAKE_FORECAST_METRICS  Forecast metrics for every synthetic run.
%
%   make_forecast_metrics()
%
% Reads each synthetic run in results/model_runs/, computes ensemble forecast
% metrics (WIS, AE, MAE, coverage, bias, peak week, onset week) per location
% and forecast week, and writes one *_fore_res_group.mat file per run to
% results/forecasts/.
%
% Run this before aggregating with MAKE_FORECAST_GROUP.
%
% See also MAKE_FORECAST_METRICS_REAL, CALCULATE_FORECAST_METRICS.

paths = setup_paths();

truth_stats = getfield(load(paths.truth_stats, 'truth_stats'), 'truth_stats');
population  = getfield(load(paths.population,  'population'),  'population');

file_list = dir(fullfile(paths.model_runs, '*_synth_*.mat'));
fprintf('Found %d synthetic run(s) in %s\n', numel(file_list), paths.model_runs);

% Define onset thresholds to calculate metrics for
onset_thresholds = [100, 150];% Add or remove thresholds as needed
%define the name of the peak variables
peak_targets = ["peak_week", "peak_inci"];

%% runs loop
% run forecast metrics for each run. no aggregation
%for run=1:size(runs_description,1)
for f_idx = 1:length(file_list)
    current_file_path = fullfile(file_list(f_idx).folder, file_list(f_idx).name);
    current_file_name = file_list(f_idx).name;
    
    fprintf('Processing: %s\n', current_file_name);
    load(current_file_path, 'forecast_struct','nickname','run_id','truth_id','strain','seed_loc','flights','Commuting'  );

    truth_current = truth_stats(strcmp({truth_stats.id}, truth_id));
    %% forcast start week loop
    for t=1:length(forecast_struct)
        
        %collect absolute week number (i start forcasting from week 2 -day 7
        forecast_struct(t).forecast_week_abs = forecast_struct(t).week_counter + 1;
        % Sum cases for each week + convert to rate over 100K
        num_times = size(forecast_struct(t).dailyIr, 2); % Get the number of time points
        num_weeks = floor(num_times / 7);
        for week = 1:num_weeks
            start_day = (week - 1) * 7 + 1;
            end_day = week * 7;
            forecast_struct(t).dailyIr_100K_week(:,week,:) =single(sum(forecast_struct(t).dailyIr(:, start_day:end_day,:), 2)./ population * 100000);
            %forecast_struct(t).dailyIu_100K_week(:,week,:) =single(sum(forecast_struct(t).dailyIu(:, start_day:end_day,:), 2)./ population * 100000);
        end

        % Calculate onset weeks for all thresholds
        for wn_idx = 1:length(onset_thresholds)
            wn = onset_thresholds(wn_idx);
            field_name = sprintf('onset%d', wn);

            [~, onset_week] = max(forecast_struct(t).dailyIr_100K_week >= wn, [], 2); % max along dimension 2 (weeks)
            onset_week(~any(forecast_struct(t).dailyIr_100K_week >= wn, 2)) = NaN; % ensable that don't reach the onset rate
            forecast_struct(t).(field_name) = single(squeeze(onset_week));
        end

        %peak week - peak amount
        [peak_inci, peak_week] = max( forecast_struct(t).dailyIr_100K_week, [], 2);
        forecast_struct(t).peak_week=int8(squeeze(peak_week));
        forecast_struct(t).peak_inci=single(squeeze(peak_inci));

        % Calculate metrics for all onset thresholds
        num_locations = size(forecast_struct(t).dailyIr_100K_week, 1);
        %% onset tresholds loop
        for wn_idx = 1:length(onset_thresholds)
            wn = onset_thresholds(wn_idx);
            field_name = sprintf('onset%d', wn);
            truth_field = sprintf('onset%d', wn);

            % set onset:
            truth_onset = truth_current.(truth_field);
            forecast_ensemble = forecast_struct(t).(field_name);

            % Get a template of the metrics structure
            metrics_template = calculate_forecast_metrics([], NaN);
            
            % Pre-allocate a structure array to hold all location metrics
            metrics_array = repmat(metrics_template, num_locations, 1);
            
            % --- Fill the pre-allocated array ---
            for loc = 1:num_locations
                truth_value = truth_onset(loc);
                forecast_values = forecast_ensemble(loc, :);
                
                % Function handles NaN truth_value internally
                metrics_array(loc) = calculate_forecast_metrics(forecast_values, truth_value);
            end
            
            % Assign the entire completed array to the struct field at once
            forecast_struct(t).([field_name '_metrics']) = metrics_array;

        end

        %% peak week and peak inci loop
       
        for p_idx = 1:length(peak_targets)
            field_name = peak_targets(p_idx);
            truth_field = field_name; % Assumes truth_current has fields 'peak_week' and 'peak_inci'
            
            % Get the vector of truth values (one per location)
            truth_values = truth_current.(truth_field);
            
            % Get the ensemble forecast [loc x ensemble_members]
            forecast_ensemble = forecast_struct(t).(field_name);
            
            % --- Pre-allocate metrics array for efficiency ---
            metrics_template = calculate_forecast_metrics([], NaN);
            metrics_array = repmat(metrics_template, num_locations, 1);
            
            % --- Fill the pre-allocated array ---
            for loc = 1:num_locations
                truth_value = truth_values(loc);
                forecast_values = forecast_ensemble(loc, :);
                
                % Function handles NaN truth_value internally
                metrics_array(loc) = calculate_forecast_metrics(forecast_values, truth_value);
            end
            
            % Assign the entire completed array to the struct field
            metrics_field_name = sprintf('%s_metrics', field_name);
            forecast_struct(t).(metrics_field_name) = metrics_array;
        end
    end
    forecast_file_name = fullfile(paths.forecasts, ...
        replace(current_file_name, ".mat", "_fore_res_group.mat"));
    fprintf('saving %s \n\n', forecast_file_name);
    save(forecast_file_name, "forecast_struct","forecast_file_name","nickname")
end

end
