function make_truth_stats_and_histogram()
%MAKE_TRUTH_STATS_AND_HISTOGRAM  Summary statistics across all synthetic truths.
%
%   make_truth_stats_and_histogram()
%
% Computes onset week (at 50/100/150/200 cases per 100K), peak week and peak
% incidence for every synthetic truth, draws the summary histograms, and
% saves data/truths/all_truths_stats.mat -- the ground truth that
% MAKE_FORECAST_METRICS scores forecasts against.
%
% Run MAKE_TRUTH_GROUPED_FILES first.
%
% See also MAKE_TRUTH, MAKE_TRUTH_GROUPED_FILES.

paths = setup_paths();

struct_truth = getfield(load(paths.truth_struct, 'struct_truth'), 'struct_truth');
population   = getfield(load(paths.population,   'population'),   'population');
%how to retrieve:
%truth_dailyIu_post_rec1 = struct_truth(1).truth_vars.truth_dailyIu_post_rec

% Specify transparency (alpha) values
alpha_value = 0.2;

black = [0 0 0];
blue = [114 147 203]./255;
red = [211 94 96]./255;
gray = [128 133 133]./255; gray=gray-0.1;
green = [132 186 91]./255;
brown = [171 104 87]./255;
purple = [144 103 167]./255;
yellow = [0.9290 0.6940 0.1250];

truth_stats = struct();


for t=1:length(struct_truth)
    truth_stats(t).id=struct_truth(t).truth_vars.truth_id;
    truth_stats(t).nick=struct_truth(t).truth_vars.truth_nick;


    truth_dailyIr_post_rec = struct_truth(t).truth_vars.truth_dailyIr_post_rec;
    truth_noisy_dailyIr_rec=struct_truth(t).truth_vars.truth_noisy_dailyIr_rec;


    num_weeks = floor(size(truth_dailyIr_post_rec, 2) / 7);

    % Sum cases for each week
    for week = 1:num_weeks
        start_day = (week - 1) * 7 + 1;
        end_day = week * 7;
        truth_stats(t).truth_week_newIr(:, week) = sum(truth_noisy_dailyIr_rec(:, start_day:end_day), 2);
    end


    truth_stats(t).alpha=struct_truth(t).truth_vars.truth_alpha_ca; %all alpha are the same
    truth_stats(t).beta=struct_truth(t).truth_vars.truth_beta_val;
    truth_stats(t).seed=struct_truth(t).truth_vars.truth_seed_code;

    %%%% WEEKLY
    
    % Normalize by population and scale to get the rate per 100,000.
    cases_100k_week=round((truth_stats(t).truth_week_newIr ./ population) * 100000);
    truth_stats(t).cases_100k_week=cases_100k_week;
    
    wn = 50; %treshould cases for onset
    [~, onset_week] = max( cases_100k_week >= wn, [], 2);
    onset_week(~any( cases_100k_week >= wn, 2)) = NaN;  % 1. Get the column index of the first 'true' value in each row.
    truth_stats(t).onset50=onset_week; % 2. Correct for rows that never reached the threshold.
 

    wn = 100; %treshould cases for onset
    [~, onset_week] = max( cases_100k_week >= wn, [], 2);
    onset_week(~any( cases_100k_week >= wn, 2)) = NaN;
    truth_stats(t).onset100=onset_week;
 
    wn = 150; %treshould cases for onset
    [~, onset_week] = max( cases_100k_week >= wn, [], 2);
    onset_week(~any( cases_100k_week >= wn, 2)) = NaN;
    truth_stats(t).onset150=onset_week;
 

    wn = 200; %treshould cases for onset
    [~, onset_week] = max( cases_100k_week >= wn, [], 2);
    onset_week(~any( cases_100k_week >= wn, 2)) = NaN;
    truth_stats(t).onset200=onset_week;

    %peak week - peak amount
    [peak_inci, peak_week] = max( cases_100k_week, [], 2);
    truth_stats(t).peak_week=peak_week;
    truth_stats(t).peak_inci=peak_inci;
    

    


    % %%%% DAILY
    % % movsum calculates the sum over a sliding window of 7 elements along the columns (dim 2).
    % weekly_cases_sum = movsum(truth_dailyIr_post_rec, 7, 2);
    % 
    % % Normalize by population and scale to get the rate per 100,000.
    % cases_100k_7daywin = round((weekly_cases_sum ./ population) * 100000);
    % 
    % n = 25; %treshould cases for onset
    % % 1. Get the column index of the first 'true' value in each row.
    % [~, onset_days] = max(cases_100k_7daywin >= n, [], 2);
    % % 2. Correct for rows that never reached the threshold.
    % onset_days(~any(cases_100k_7daywin >= n, 2)) = NaN;
    % truth_stats(t).onset25=onset_days;
    % 
    % n = 50; %treshould cases for onset
    % [~, onset_days] = max(cases_100k_7daywin >= n, [], 2);
    % onset_days(~any(cases_100k_7daywin >= n, 2)) = NaN;
    % truth_stats(t).onset50=onset_days;
    % 
    % 
    % n = 100;
    % [~, onset_days] = max(cases_100k_7daywin >= n, [], 2);
    % onset_days(~any(cases_100k_7daywin >= n, 2)) = NaN;
    % truth_stats(t).onset100=onset_days;
    % 
    % n = 200;
    % [~, onset_days] = max(cases_100k_7daywin >= n, [], 2);
    % onset_days(~any(cases_100k_7daywin >= n, 2)) = NaN;
    % truth_stats(t).onset200=onset_days;

    %truth_stats(t).onsetmax=

end

figure()
nexttile;
for t=1:length(struct_truth)
    for l=1:length(cases_100k_week)
        hold on
        plot(truth_stats(t).cases_100k_week(l,:),'LineWidth',0.5,'Color',[blue, alpha_value+0.2]);
    end
end
yline([50 100 150 200],"--", 'LineWidth',1)
xlabel("week")
ylabel("cases/100K")
ylim([0 4000])
text(xlim*[1; 0], 50, ' 50', 'VerticalAlignment', 'baseline', 'FontSize', 7,"FontWeight","bold")
text(xlim*[1; 0], 100, ' 100', 'VerticalAlignment', 'baseline', 'FontSize', 7,"FontWeight","bold")
text(xlim*[1; 0], 150, ' 150', 'VerticalAlignment', 'baseline', 'FontSize', 7,"FontWeight","bold")
text(xlim*[1; 0], 200, ' 200', 'VerticalAlignment', 'baseline', 'FontSize', 7,"FontWeight","bold")
title("Weekly incidence")


nexttile("east");

histogram(vertcat(truth_stats.peak_inci),80,'Orientation', 'horizontal')
xlabel("counts")
ylim([0 4000])
title("incidence at peak")
set(gca, 'YAxisLocation', 'right')

%%%%%%
figure()
tiledlayout(3,2);
nexttile(1, [1 2]);
histogram(vertcat(truth_stats.peak_week));
xlabel("week")
title("peak week")

nexttile();
histogram(vertcat(truth_stats.onset50));
xlim([1 15])
xlabel("week")
title("week onset 50/100k")

nexttile;
histogram(vertcat(truth_stats.onset100));
xlim([1 15])
xlabel("week")
title("week onset 100/100k")

nexttile;
histogram(vertcat(truth_stats.onset150));
xlim([1 15])
xlabel("week")
title("week onset 150/100k")

nexttile;
histogram(vertcat(truth_stats.onset200));
xlim([1 15])
xlabel("week")
title("week onset 200/100k")
hold off



save(paths.truth_stats, "truth_stats");
fprintf('Saved %s\n', paths.truth_stats);

end