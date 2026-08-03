function export_fan_data()
%EXPORT_FAN_DATA  Export forecast-ensemble spread + truth to tidy CSV for R.
%
%   export_fan_data()
%
% Companion to src/plotting/plot_fan_forecast.R (the fan plots for the
% reviewer response). This is a one-off extraction, NOT part of run_pipeline.
%
% For a handful of selected runs and a handful of selected locations it
% collapses the 150-member forecast ensemble to mean + quantiles of
% WEEKLY NEW CASES PER 100,000, for every forecast start week, and writes:
%
%   <OUT_DIR>/fan_forecast_synth.csv   one row per run x forecast start week x location x week
%   <OUT_DIR>/fan_truth_synth.csv      one row per truth x location x week
%   <OUT_DIR>/fan_forecast_real.csv    idem, real-incidence runs
%   <OUT_DIR>/fan_truth_real.csv       idem, reported incidence
%
% Units follow src/forecast/make_forecast_metrics.m exactly:
%   week      = 1:floor(num_times/7)
%   start_day = (week-1)*7+1 ;  end_day = week*7
%   value     = sum(dailyIr(:, start_day:end_day, :), 2) ./ population * 100000
% i.e. weekly NEW cases per 100k. Not daily, not cumulative.
%
% Everything that is meant to be edited sits in the CONFIG block below.
% Paths are absolute on purpose: the raw .mat files live in the *dev* repo,
% which is not part of this project tree.
%
% Runtime note: the per-run forecast files are 0.5-3 GB. They are read with a
% plain LOAD (~6 s for a synthetic run, ~80 s for a real run); MATFILE lazy
% indexing was measured to be ~25x slower on these files, so it is not used.
%
% See also PLOT_FAN_FORECAST (R), MAKE_FORECAST_METRICS.

%% ─────────────────────── CONFIG ────────────────────────────────────────────

% --- roots -----------------------------------------------------------------
% Raw .mat files live in the dev repo: absolute path, edit here.
P.dev_root = ['/Users/matteoperini/Library/CloudStorage/Box-Box/Matteo Perini/' ...
              '13_NA-returns/Model/NA_SEIR-EAKF-flights-dev'];

% This project. '' = infer from this file's location (works from a worktree too).
% Absolute alternative:
%   '/Users/matteoperini/Library/CloudStorage/Box-Box/Matteo Perini/13_NA-returns/Model/NA_SEIR-EAKF_forecast'
P.pub_root = '';
if isempty(P.pub_root)
    P.pub_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
end

% --- inputs (all in the dev repo) ------------------------------------------
P.forecasts_dir    = fullfile(P.dev_root, 'Forecasts');
P.truth_stats_file = fullfile(P.dev_root, 'Truths', '1118_all_truths_stats.mat'); % truth_stats(1x35)
P.real_stats_file  = fullfile(P.dev_root, 'Truths', '1211_real_stats.mat');       % real_stats
P.population_file  = fullfile(P.dev_root, 'population.mat');
P.statecodes_file  = fullfile(P.dev_root, 'statecodes.mat');

% Public-repo equivalents, if you would rather not touch the dev repo:
%   P.truth_stats_file = fullfile(P.pub_root, 'data', 'truths', 'all_truths_stats.mat');
%   P.real_stats_file  = fullfile(P.pub_root, 'data', 'truths', 'real_stats.mat');
%   P.population_file  = fullfile(P.pub_root, 'data', 'population.mat');
%   P.statecodes_file  = fullfile(P.pub_root, 'data', 'statecodes.mat');

% --- output ----------------------------------------------------------------
P.out_dir = fullfile(P.pub_root, 'results', 'csv');

% --- what to export --------------------------------------------------------
P.do_synth = true;
P.do_real  = true;

% Locations: row index into statecodes / population (see data/statecodes.csv).
% Export a superset; pick the four to plot with STATES in plot_fan_forecast.R.
P.loc_rows = [84, 10, 66, 22, 55];
% Texas, California, Ontario, Estado de Mexico, New York

% Synthetic runs: the cross product of these three lists is looked up in
% P.forecasts_dir as  *_synth_tr??_<strain>_<seed>_<config>_fore_res_group.mat
P.synth_strains   = {'ls','lo','me','hi','hs'};   % beta = 0.8, 1, 2, 3, 4
P.synth_seed_locs = {'GA','NY'};                   % seeding state of the truth
% Seeding matters for onset-aligned figures: a truth seeded in a state you also plot
% puts that state's onset at week 2, leaving no lead time to forecast it. GA is a hub
% that is not one of the four plotted states, so all four get a proper run-up; NY is
% exported alongside for comparison. Pick one with SEED_LOCS in plot_fan_forecast.R.

% The full flights x commuting factorial, which is what the figures contrast.
P.synth_configs   = {'f_n_pois','nf_n_pois','f_p_pois','nf_p_pois'};
% The eight configs map to these run-number blocks (35 truths each, tr01..tr35):
%   001-035 f_n_pois   036-070 nf_n_pois  071-105 f_p_pois  106-140 nf_p_pois
%   201-235 f_n_det    236-270 nf_n_det   271-305 f_p_det   306-340 nf_p_det

% Real runs: matched as  *_<name>_fore_real_stats.mat
P.real_runs = {'601_real_nf_n_pois', '602_real_f_n_pois', ...
               '603_real_nf_p_pois', '604_real_f_p_pois'};
% deterministic counterparts: 701_real_nf_n_det 702_real_f_n_det
%                             703_real_nf_p_det 704_real_f_p_det

% --- how much of each forecast to keep -------------------------------------
P.quantiles          = [0.05 0.25 0.50 0.75 0.95];  % -> columns q05 q25 q50 q75 q95
P.weeks_before_start = 1;    % observed weeks kept before the forecast start,
                             % so the fan visually attaches to the truth line
P.max_horizon_weeks  = Inf;  % weeks of forecast kept after the start week
P.forecast_weeks     = [];   % [] = every forecast start week; or e.g. [8 16 24]

%% ─────────────────────── END CONFIG ────────────────────────────────────────

if ~isfolder(P.out_dir), mkdir(P.out_dir); end

population = load_one(P.population_file, 'population');
statecodes = load_one(P.statecodes_file, 'statecodes');

locs = build_loc_table(statecodes, population, P.loc_rows);
fprintf('Locations:\n');
for i = 1:height(locs)
    fprintf('  row %2d  %-20s %s  pop=%.0f\n', ...
        locs.loc_row(i), locs.loc_name(i), locs.country(i), locs.population(i));
end

qnames = arrayfun(@(p) sprintf('q%02d', round(p*100)), P.quantiles, 'UniformOutput', false);

%% ─────────────────────── SYNTHETIC ─────────────────────────────────────────
if P.do_synth
    fprintf('\n===== SYNTHETIC =====\n');
    truth_stats = load_one(P.truth_stats_file, 'truth_stats');

    % --- truth trajectories -------------------------------------------------
    truth_tbl = table();
    wanted = {};
    for s = 1:numel(P.synth_strains)
        for l = 1:numel(P.synth_seed_locs)
            wanted{end+1} = sprintf('%s_%s', P.synth_strains{s}, P.synth_seed_locs{l}); %#ok<AGROW>
        end
    end

    for k = 1:numel(truth_stats)
        nick = char(truth_stats(k).nick);              % e.g. tr01_ls_NY
        parts = split(string(nick), '_');              % [trNN, strain, seed]
        key = sprintf('%s_%s', parts(2), parts(3));
        if ~any(strcmp(key, wanted)), continue; end

        cw = truth_stats(k).cases_100k_week;           % [96 x 52], weekly per 100k
        t  = long_truth(cw, locs, NaT);
        t.dataset  = repmat("synth",          height(t), 1);
        t.truth_id = repmat(string(truth_stats(k).id), height(t), 1);
        t.nick     = repmat(string(nick),     height(t), 1);
        t.strain   = repmat(parts(2),         height(t), 1);
        t.beta     = repmat(truth_stats(k).beta, height(t), 1);
        t.seed_loc = repmat(parts(3),         height(t), 1);
        truth_tbl  = [truth_tbl; t]; %#ok<AGROW>
    end
    truth_tbl = movevars(truth_tbl, ...
        {'dataset','truth_id','nick','strain','beta','seed_loc'}, 'Before', 1);

    out = fullfile(P.out_dir, 'fan_truth_synth.csv');
    writetable(truth_tbl, out);
    fprintf('wrote %s  (%d rows)\n', out, height(truth_tbl));

    % --- forecast ensembles -------------------------------------------------
    fore_tbl = table();
    for s = 1:numel(P.synth_strains)
        for l = 1:numel(P.synth_seed_locs)
            for c = 1:numel(P.synth_configs)
                pat = sprintf('*_synth_tr*_%s_%s_%s_fore_res_group.mat', ...
                    P.synth_strains{s}, P.synth_seed_locs{l}, P.synth_configs{c});
                d = dir(fullfile(P.forecasts_dir, pat));
                if isempty(d)
                    warning('No forecast file matching %s', pat); continue
                end
                if numel(d) > 1
                    warning('%d files match %s, using %s', numel(d), pat, d(1).name);
                end
                f = fullfile(d(1).folder, d(1).name);
                try
                    fore_tbl = [fore_tbl; one_run(f, locs, population, P, qnames, 'synth', NaT)]; %#ok<AGROW>
                catch ME
                    warning('Skipping %s: %s', d(1).name, ME.message);
                end
            end
        end
    end

    out = fullfile(P.out_dir, 'fan_forecast_synth.csv');
    writetable(fore_tbl, out);
    fprintf('wrote %s  (%d rows)\n', out, height(fore_tbl));
end

%% ─────────────────────── REAL ──────────────────────────────────────────────
if P.do_real
    fprintf('\n===== REAL =====\n');
    real_stats = load_one(P.real_stats_file, 'real_stats');

    % Calendar date of absolute week 1, from the slice bookkeeping
    week1_date = real_stats.slice_start_dates(1) - days(7*(real_stats.slice_start_week(1)-1));
    fprintf('Week 1 starts %s\n', string(week1_date, 'dd-MMM-yyyy'));

    % --- truth trajectory ---------------------------------------------------
    t = long_truth(real_stats.cases_100k_week, locs, week1_date);
    t.dataset  = repmat("real",  height(t), 1);
    t.truth_id = repmat("tr00",  height(t), 1);
    t.nick     = repmat("real",  height(t), 1);
    t.strain   = repmat("",      height(t), 1);
    t.beta     = nan(height(t), 1);
    t.seed_loc = repmat("",      height(t), 1);
    t = movevars(t, {'dataset','truth_id','nick','strain','beta','seed_loc'}, 'Before', 1);

    out = fullfile(P.out_dir, 'fan_truth_real.csv');
    writetable(t, out);
    fprintf('wrote %s  (%d rows)\n', out, height(t));

    % --- forecast ensembles -------------------------------------------------
    fore_tbl = table();
    for r = 1:numel(P.real_runs)
        pat = sprintf('*%s_fore_real_stats.mat', P.real_runs{r});
        d = dir(fullfile(P.forecasts_dir, pat));
        if isempty(d)
            warning('No forecast file matching %s', pat); continue
        end
        f = fullfile(d(1).folder, d(1).name);
        try
            fore_tbl = [fore_tbl; one_run(f, locs, population, P, qnames, 'real', week1_date)]; %#ok<AGROW>
        catch ME
            warning('Skipping %s: %s', d(1).name, ME.message);
        end
    end

    out = fullfile(P.out_dir, 'fan_forecast_real.csv');
    writetable(fore_tbl, out);
    fprintf('wrote %s  (%d rows)\n', out, height(fore_tbl));
end

fprintf('\nDone.\n');
end

%% ─────────────────────── HELPERS ───────────────────────────────────────────

function v = load_one(file, name)
if ~isfile(file), error('Missing input file: %s', file); end
S = load(file, name);
v = S.(name);
end

function locs = build_loc_table(statecodes, population, rows)
rows = rows(:);
locs = table(rows, 'VariableNames', {'loc_row'});
locs.loc_name   = string(statecodes.Var2(rows));
locs.country    = string(statecodes.Var3(rows));
locs.population = population(rows);
end

function t = long_truth(cases_100k_week, locs, week1_date)
% cases_100k_week : [num_loc_all x num_weeks]  ->  long table for the chosen rows
sub    = cases_100k_week(locs.loc_row, :);
nloc   = size(sub, 1);
nweeks = size(sub, 2);

week = repmat(1:nweeks, nloc, 1);
li   = repmat((1:nloc)', 1, nweeks);

t = table();
t.loc_row    = locs.loc_row(li(:));
t.loc_name   = locs.loc_name(li(:));
t.country    = locs.country(li(:));
t.week       = week(:);
t.week_date  = week_dates(week(:), week1_date);
t.truth_100k = sub(:);
end

function d = week_dates(week, week1_date)
% ISO 8601 so R's as.Date() parses it without a format string or a locale.
if isnat(week1_date)
    d = NaT(numel(week), 1);
else
    d = week1_date + days(7*(week - 1));
end
d.Format = 'yyyy-MM-dd';
end

function tbl = one_run(file, locs, population, P, qnames, dataset, week1_date)
%ONE_RUN  Ensemble summary for every forecast start week of one run file.

fprintf('loading %s\n', file);
tic;
S  = load(file, 'forecast_struct');
fs = S.forecast_struct;
clear S
fprintf('  %d forecast start weeks, loaded in %.1f s\n', numel(fs), toc);

meta = parse_nickname(char(fs(1).nickname));

nloc = height(locs);
nq   = numel(P.quantiles);
rows = locs.loc_row;

chunks = cell(numel(fs), 1);
for t = 1:numel(fs)
    fw = double(fs(t).forecast_week_abs);
    if ~isempty(P.forecast_weeks) && ~ismember(fw, P.forecast_weeks), continue; end

    W = weekly_100k(fs(t), rows, population);   % [nloc x nweeks x nens]
    nweeks = size(W, 2);

    w_lo = max(1,      fw - P.weeks_before_start);
    w_hi = min(nweeks, fw + P.max_horizon_weeks - 1);
    keep = w_lo:w_hi;
    if isempty(keep), continue; end

    Wk = W(:, keep, :);
    mu = mean(Wk, 3);                       % [nloc x nk]
    qv = quantile(Wk, P.quantiles, 3);      % [nloc x nk x nq]
    nk = numel(keep);

    week = repmat(keep,        nloc, 1);
    li   = repmat((1:nloc)',   1,    nk);

    c = table();
    c.loc_row       = locs.loc_row(li(:));
    c.loc_name      = locs.loc_name(li(:));
    c.country       = locs.country(li(:));
    c.forecast_week = repmat(fw, nloc*nk, 1);
    c.week          = week(:);
    c.horizon       = week(:) - fw + 1;      % 1 = first forecast week, <=0 = observed
    c.is_forecast   = double(week(:) >= fw);
    c.week_date     = week_dates(week(:), week1_date);
    c.mean          = mu(:);
    for k = 1:nq
        c.(qnames{k}) = reshape(qv(:, :, k), [], 1);
    end
    chunks{t} = c;
end

tbl = vertcat(chunks{:});
if isempty(tbl), return; end

n = height(tbl);
tbl.dataset   = repmat(string(dataset),      n, 1);
tbl.run_num   = repmat(string(meta.num),     n, 1);
tbl.nickname  = repmat(string(meta.nickname),n, 1);
tbl.truth_id  = repmat(string(fs(1).truth_id), n, 1);
tbl.strain    = repmat(string(meta.strain),  n, 1);
tbl.beta      = repmat(meta.beta,            n, 1);
tbl.seed_loc  = repmat(string(meta.seed),    n, 1);
tbl.flights   = repmat(string(meta.flights), n, 1);
tbl.commuting = repmat(string(meta.comm),    n, 1);
tbl.stoch     = repmat(string(meta.stoch),   n, 1);

tbl = movevars(tbl, {'dataset','run_num','nickname','truth_id','strain','beta', ...
                     'seed_loc','flights','commuting','stoch'}, 'Before', 1);
end

function W = weekly_100k(fst, rows, population)
%WEEKLY_100K  [nloc x nweeks x nens] of weekly new cases per 100k.
% Uses the precomputed dailyIr_100K_week when present, otherwise rebuilds it
% from dailyIr with the exact transform of make_forecast_metrics.m.
if isfield(fst, 'dailyIr_100K_week') && ~isempty(fst.dailyIr_100K_week)
    W = double(fst.dailyIr_100K_week(rows, :, :));
    return
end
d      = double(fst.dailyIr(rows, :, :));
nweeks = floor(size(d, 2) / 7);
W      = zeros(numel(rows), nweeks, size(d, 3));
pop    = population(rows);
for week = 1:nweeks
    start_day = (week - 1)*7 + 1;
    end_day   = week*7;
    W(:, week, :) = sum(d(:, start_day:end_day, :), 2) ./ pop * 100000;
end
end

function m = parse_nickname(nickname)
%PARSE_NICKNAME  e.g. 001_synth_tr01_ls_NY_f_n_pois  /  601_real_nf_n_pois
m = struct('nickname', nickname, 'num', '', 'strain', '', 'beta', NaN, ...
           'seed', '', 'flights', '', 'comm', '', 'stoch', '');

beta_of = containers.Map({'ls','lo','me','hi','hs'}, {0.8, 1, 2, 3, 4});

tok = regexp(nickname, ['^(?<num>\d+)_synth_tr\d+_(?<strain>[a-z]{2})_(?<seed>[A-Z]{2})_' ...
                        '(?<flights>n?f)_(?<comm>[np])_(?<stoch>pois|det)$'], 'names');
if ~isempty(tok)
    m.num = tok.num; m.strain = tok.strain; m.seed = tok.seed;
    m.flights = tok.flights; m.comm = tok.comm; m.stoch = tok.stoch;
    if isKey(beta_of, tok.strain), m.beta = beta_of(tok.strain); end
    return
end

tok = regexp(nickname, ['^(?<num>\d+)_real_(?<flights>n?f)_(?<comm>[np])_' ...
                        '(?<stoch>pois|det)$'], 'names');
if ~isempty(tok)
    m.num = tok.num; m.flights = tok.flights; m.comm = tok.comm; m.stoch = tok.stoch;
    return
end

warning('Could not parse nickname "%s"', nickname);
end
