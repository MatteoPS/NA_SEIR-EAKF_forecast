% loads aggregated REAL DATA forecast metrics and exports
% relative bar data to a CSV

clearvars; clc;

%% ========================================================================
%% CONFIGURATION - must match your aggregation settings
%% ========================================================================
group_by_country = false;
group_by_wave    = false;
pois_only        = true;
fixedbaseline    = false;

if fixedbaseline
    time_windows_to_average = {-8:-6; -5:-3; -2:0};
    time_windows_names = {"m8m6";"m5m3"; "m2p0"};
    baseline_name = "m8m6";
else
    time_windows_to_average = {-8:6};
    time_windows_names = {"all"};
end



%% ========================================================================
%% END CONFIGURATION
%% ========================================================================

%% --- 1. Parameters ---

% Input file - auto-selected from configuration (mirrors plotting script)
if group_by_country && group_by_wave
    metrics_file_path = 'Forecasts_real_agg/real_data_aggregated_by_country_and_wave.mat';
    agg_type          = 'by_country_and_wave';
elseif group_by_country && ~group_by_wave
    if pois_only
        metrics_file_path = 'Forecasts_real_agg/real_data_aggregated_pois_by_country_all_waves.mat';
    else
        metrics_file_path = 'Forecasts_real_agg/real_data_aggregated_by_country_all_waves.mat';
    end
    agg_type = 'by_country_all_waves';
elseif ~group_by_country && group_by_wave
    metrics_file_path = 'Forecasts_real_agg/real_data_aggregated_by_wave_all_countries.mat';
    agg_type          = 'by_wave_all_countries';
else
    metrics_file_path = 'Forecasts_real_agg/real_data_aggregated_all_aggregated.mat';
    agg_type          = 'all_aggregated';
end

if fixedbaseline
    baseline_suffix = sprintf('_base%s', baseline_name);
else
    baseline_suffix = '';
end

if pois_only
    out_path = sprintf('Output/rel_bars_real_pois_%s%s.csv', agg_type, baseline_suffix);
else
    out_path = sprintf('Output/rel_bars_real_%s%s.csv', agg_type, baseline_suffix);
end

% Targets, metrics, averaging window
targets_to_plot        = {'onset50', 'onset100'};
metrics_to_plot        = {'mean_mae', 'mean_wis'};

bar_cap                = 1.5;

fprintf('\n========================================\n');
fprintf('CSV EXPORT CONFIGURATION:\n');
fprintf('  Group by Country : %s\n', string(group_by_country));
fprintf('  Group by Wave    : %s\n', string(group_by_wave));
fprintf('  Pois only        : %s\n', string(pois_only));
fprintf('  Loading file     : %s\n', metrics_file_path);
fprintf('  Output path      : %s\n', out_path);
fprintf('========================================\n\n');

%% --- 2. Load Data ---
fprintf('Loading metrics from: %s\n', metrics_file_path);
loaded_data = load(metrics_file_path);

% Define expected field order (mirrors the plotting script)
if group_by_country && group_by_wave
    countries      = ["CA", "US", "MX"];
    waves          = ["Start", "Cutoff1", "Cutoff2"];
    if pois_only
        model_prefixes = ["nf_p_pois","f_p_pois","nf_n_pois","f_n_pois"];
    else
        model_prefixes = ["nf_p_det","nf_p_pois","f_p_det","f_p_pois", ...
                          "nf_n_det","nf_n_pois","f_n_det","f_n_pois"];
    end
    
    file_order = strings(1, length(waves)*length(countries)*length(model_prefixes));
    idx = 1;
    for w = 1:length(waves)
        for c = 1:length(countries)
            for m = 1:length(model_prefixes)
                file_order(idx) = sprintf('%s_%s_%s', model_prefixes(m), countries(c), waves(w));
                idx = idx + 1;
            end
        end
    end
elseif group_by_country && ~group_by_wave
    if pois_only
        file_order = ["nf_p_pois_CA","f_p_pois_CA","nf_n_pois_CA","f_n_pois_CA", ...
                      "nf_p_pois_US","f_p_pois_US","nf_n_pois_US","f_n_pois_US", ...
                      "nf_p_pois_MX","f_p_pois_MX","nf_n_pois_MX","f_n_pois_MX"];
    else
        file_order = ["nf_p_det_CA","nf_p_pois_CA","f_p_det_CA","f_p_pois_CA", ...
                      "nf_n_det_CA","nf_n_pois_CA","f_n_det_CA","f_n_pois_CA", ...
                      "nf_p_det_US","nf_p_pois_US","f_p_det_US","f_p_pois_US", ...
                      "nf_n_det_US","nf_n_pois_US","f_n_det_US","f_n_pois_US", ...
                      "nf_p_det_MX","nf_p_pois_MX","f_p_det_MX","f_p_pois_MX", ...
                      "nf_n_det_MX","nf_n_pois_MX","f_n_det_MX","f_n_pois_MX"];
    end
elseif ~group_by_country && group_by_wave
    if pois_only
        file_order = ["nf_p_pois_Start","nf_p_pois_Cutoff1","nf_p_pois_Cutoff2", ...
                      "f_p_pois_Start","f_p_pois_Cutoff1","f_p_pois_Cutoff2", ...
                      "nf_n_pois_Start","nf_n_pois_Cutoff1","nf_n_pois_Cutoff2", ...
                      "f_n_pois_Start","f_n_pois_Cutoff1","f_n_pois_Cutoff2"];
    else
        file_order = ["nf_p_det_Start","nf_p_det_Cutoff1","nf_p_det_Cutoff2", ...
                      "nf_p_pois_Start","nf_p_pois_Cutoff1","nf_p_pois_Cutoff2", ...
                      "f_p_det_Start","f_p_det_Cutoff1","f_p_det_Cutoff2", ...
                      "f_p_pois_Start","f_p_pois_Cutoff1","f_p_pois_Cutoff2", ...
                      "nf_n_det_Start","nf_n_det_Cutoff1","nf_n_det_Cutoff2", ...
                      "nf_n_pois_Start","nf_n_pois_Cutoff1","nf_n_pois_Cutoff2", ...
                      "f_n_det_Start","f_n_det_Cutoff1","f_n_det_Cutoff2", ...
                      "f_n_pois_Start","f_n_pois_Cutoff1","f_n_pois_Cutoff2"];
    end
else
    if pois_only
        file_order = ["nf_p_pois","f_p_pois","nf_n_pois","f_n_pois"];
    else
        file_order = ["nf_p_det","nf_p_pois","f_p_det","f_p_pois", ...
                      "nf_n_det","nf_n_pois","f_n_det","f_n_pois"];
    end
end

% Ensure loaded_data matches file_order exactly so orderfields() works automatically
actual_fields = fieldnames(loaded_data);
expected_fields = cellstr(file_order);

% 1. Remove extra fields from loaded_data (e.g., 'det' models when pois_only = true)
fields_to_remove = setdiff(actual_fields, expected_fields);
if ~isempty(fields_to_remove)
    loaded_data = rmfield(loaded_data, fields_to_remove);
end

% 2. Drop expected fields that might be missing from loaded_data
actual_fields_after = fieldnames(loaded_data);
missing_fields = setdiff(expected_fields, actual_fields_after);
final_order = setdiff(expected_fields, missing_fields, 'stable');

% 3. Apply the perfect reordering
loaded_data = orderfields(loaded_data, final_order);
nicknames = string(fieldnames(loaded_data));

%% --- 3. Restructure data to always include a slice dimension ---
% After this block: loaded_data.(nickname).(slice_name).(target)
if group_by_wave
    % Wave is encoded in the field name (e.g. nf_p_det_Start).
    % Restructure to: loaded_data.(model_base).(wave).(target)
    wave_set = strings(0);
    for nk = 1:length(nicknames)
        parts = split(nicknames(nk), "_");
        wave_set(end+1) = parts(end);
    end
    slice_names = unique(wave_set, 'stable');

    temp_data = struct();
    for nk = 1:length(nicknames)
        nickname   = nicknames(nk);
        parts      = split(nickname, "_");
        wave_name  = parts(end);
        model_base = strjoin(parts(1:end-1), "_");
        if ~isfield(temp_data, model_base)
            temp_data.(model_base) = struct();
        end
        temp_data.(model_base).(wave_name) = loaded_data.(nickname);
    end
    loaded_data = temp_data;
    nicknames   = string(fieldnames(loaded_data));
else
    % No wave: wrap each model in a dummy "all_data" slice
    slice_names = "all_data";
    temp_data   = struct();
    for nk = 1:length(nicknames)
        nickname = nicknames(nk);
        temp_data.(nickname).all_data = loaded_data.(nickname);
    end
    loaded_data = temp_data;
end

fprintf('Found %d model(s) and %d slice(s).\n', length(nicknames), length(slice_names));

%% --- 3b. Resolve fixed baseline time window (used when fixedbaseline == true) ---
% When fixedbaseline is true the baseline value is always computed over the
% window identified by baseline_name, regardless of the model's current window.
if fixedbaseline
    baseline_win_idx = find(string(time_windows_names) == baseline_name, 1);
    if isempty(baseline_win_idx)
        error('baseline_name "%s" not found in time_windows_names.', baseline_name);
    end
    fixed_baseline_time_window = time_windows_to_average{baseline_win_idx};
    fixed_baseline_window_label = baseline_name;
    fprintf('Fixed baseline window : %s  (weeks %d to %d)\n', ...
        baseline_name, fixed_baseline_time_window(1), fixed_baseline_time_window(end));
end

%% --- 4. Main Loop: compute relative values and accumulate rows ---
csv_rows = {};

for s_i = 1:length(slice_names)
    slice_name = slice_names(s_i);
    fprintf('Processing slice: %s\n', slice_name);

    for r = 1:length(targets_to_plot)
        target_to_plot = targets_to_plot{r};

        for c = 1:length(metrics_to_plot)
            metric_to_plot = metrics_to_plot{c};

            % --- NEW LOOP: Iterate over Time Windows ---
            for w_idx = 1:length(time_windows_to_average)
                current_time_window = time_windows_to_average{w_idx};
                current_window_name = time_windows_names{w_idx};

                for nk = 1:length(nicknames)
                    nickname   = nicknames(nk);
                    slice_data = loaded_data.(nickname).(slice_name);

                    % --- Baseline construction ---
                    parts    = split(nickname, "_");
                    parts(1) = "nf";  % No Flight
                    parts(2) = "p";   % Patch
                    if ~pois_only
                        parts(3) = "det"; % Deterministic baseline
                    end
                    current_baseline_nickname = join(parts, "_");

                    % --- Baseline average ---
                    % When fixedbaseline == true the denominator is always
                    % computed over the fixed baseline window (baseline_name),
                    % not the model's current time window.
                    if fixedbaseline
                        tw_for_baseline        = fixed_baseline_time_window;
                        baseline_window_label  = fixed_baseline_window_label;
                    else
                        tw_for_baseline        = current_time_window;
                        baseline_window_label  = current_window_name;
                    end

                    baseline_val = NaN;
                    if isfield(loaded_data, current_baseline_nickname) && ...
                       isfield(loaded_data.(current_baseline_nickname).(slice_name), target_to_plot)
                        base_data    = loaded_data.(current_baseline_nickname).(slice_name).(target_to_plot);
                        [b_vals, ~]  = extract_series_data(base_data, metric_to_plot, tw_for_baseline);
                        baseline_val = mean(b_vals, 'omitnan');
                    end

                    % --- Model average and relative value ---
                    curr_rel_val   = NaN;
                    avg_num_sample = NaN;
                    if isfield(slice_data, target_to_plot)
                        [g_vals, g_samples] = extract_series_data( ...
                            slice_data.(target_to_plot), metric_to_plot, current_time_window);
                        group_val      = mean(g_vals,    'omitnan');
                        avg_num_sample = mean(g_samples, 'omitnan');
                        if ~isnan(baseline_val) && baseline_val ~= 0
                            curr_rel_val = group_val / baseline_val;
                        end
                    end

                    % --- Parse label / style components ---
                    [model_label, flights, commuting, country, wave, stochastic] = ...
                        parse_model_config_csv(nickname, group_by_country, group_by_wave, pois_only);

                    capped = ~isnan(curr_rel_val) && curr_rel_val > bar_cap;

                    % Append row with time_window and baseline_window
                    csv_rows{end+1} = { ...
                        char(nickname),    char(model_label), ...
                        char(slice_name),  target_to_plot,    metric_to_plot, ...
                        char(current_window_name), ...
                        char(baseline_window_label), ... % <-- fixed or matching window used for baseline
                        curr_rel_val,      avg_num_sample, ...
                        char(flights),     char(commuting), ...
                        char(country),     char(wave),        char(stochastic), ...
                        double(capped)};
                end % nickname loop
            end % window loop
        end % metric loop
    end % target loop
end % slice loop

%% --- 5. Write CSV ---
fid = fopen(out_path, 'w');
fprintf(fid, 'nickname,model_label,slice,target,metric,time_window,baseline_window,rel_val,n_samples,flights,commuting,country,wave,stochastic,capped\n');
for k = 1:length(csv_rows)
    row = csv_rows{k};
    fprintf(fid, '%s,%s,%s,%s,%s,%s,%s,%.6f,%.1f,%s,%s,%s,%s,%s,%d\n', ...
        row{1}, row{2}, row{3}, row{4}, row{5}, row{6}, row{7}, ...
        row{8}, row{9}, ...
        row{10}, row{11}, row{12}, row{13}, row{14}, row{15});
end
fclose(fid);
fprintf('CSV saved to: %s\n', out_path);

%% =========================================================================
%  LOCAL HELPER FUNCTIONS
%  =========================================================================

function [series_values, num_samples] = extract_series_data(target_data, metric_to_plot, x_week_range)
series_values = NaN(1, length(x_week_range));
num_samples   = NaN(1, length(x_week_range));
for j = 1:length(x_week_range)
    current_week = x_week_range(j);
    if current_week >= 0
        bin_name = sprintf('week_p%d', current_week);
    else
        bin_name = sprintf('week_m%d', abs(current_week));
    end
    if isfield(target_data, bin_name) && isfield(target_data.(bin_name), metric_to_plot)
        series_values(j) = target_data.(bin_name).(metric_to_plot);
        if isfield(target_data.(bin_name), 'num_samples')
            num_samples(j) = target_data.(bin_name).num_samples;
        end
    end
end
end

function [model_label, flights, commuting, country, wave, stochastic] = ...
    parse_model_config_csv(nickname, group_by_country, group_by_wave, pois_only)
% Parses a model nickname and returns individual metadata components for CSV.
% Mirrors the logic of parse_model_config in the plotting script.

settings  = split(nickname, "_");
flights   = settings(1);   % "nf" or "f"
commuting = settings(2);   % "p"  or "n"

% Country
if group_by_country
    if group_by_wave
        country = settings(end-1);   % format: model_Country_Wave
    else
        country = settings(end);     % format: model_Country
    end
else
    country = "ALL";
end

% Wave
if group_by_wave
    wave = settings(end);
else
    wave = "ALL";
end

% Stochastic flag
if contains(nickname, "_pois")
    stochastic = "pois";
else
    stochastic = "det";
end

% Human-readable label (mirrors parse_model_config in plotting script)
lab = strings(1, 3);
if flights == "nf", lab(1) = "No Flight"; else, lab(1) = "Flight";   end
if commuting == "n", lab(2) = "Network";  else, lab(2) = "Patch";    end

if group_by_country && group_by_wave
    lab(3) = sprintf("%s-%s", country, wave);
elseif group_by_country
    lab(3) = country;
elseif group_by_wave
    lab(3) = wave;
else
    lab(3) = "All";
end

if ~pois_only
    if stochastic == "det"
        lab(3) = lab(3) + " - Det";
    else
        lab(3) = lab(3) + " - Stoc";
    end
end

model_label = strjoin(lab, " - ");
end