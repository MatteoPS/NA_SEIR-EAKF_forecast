%Comment the last two line of MODEL_RUN()
%to avoid counting the time to save variable and plotting

function Test_runtime(run_name)


runinfo_file=strjoin([ "Model_Runs/" run_name "-runinfo.mat"],'');

startTime = datetime('now');
MODEL_RUN(run_name); % Run your model
endTime = datetime('now');
runtime = seconds(endTime - startTime);
run_name ="Runtime " + run_name + " = " + runtime + " seconds";

save(runinfo_file, "run_name");

