local function dotnet_build(file_path)
	local uv = vim.uv or vim.loop
	local stdout = uv.new_pipe()
	local stderr = uv.new_pipe()

	local options = {
		args = { "dotnet", "build", file_path },
		stdio = { nil, stdout, stderr },
		cwd = vim.fn.getcwd(),
	}

	uv.spawn("dotnet", options, function(code, signal)
		stdout:close()
		stderr:close()

		vim.schedule(function()
			if code == 0 then
				vim.notify("✅ Build succeeded!", vim.log.levels.INFO)
			else
				vim.notify("❌ Build failed! Check terminal for details.", vim.log.levels.ERROR)
			end
		end)
	end)
end

local function dotnet_build2(file)
	local command = { "dotnet", "build", file }
	local job_id = vim.fn.jobstart(command, {
		on_exit = function(job_id, data, event)
			print("Exit code: " .. data.exit_code)
		end
	})
end

local function dotnet_run()
	exec_callback_on_project(function(file)
		vim.cmd("edit " .. file)
	end)
end

local function project_actions(file)
	local actions = {
		"Edit",
		"Build",
		"Debug",
		"Run",
	}

	require("fzf-lua").fzf_exec(actions, {
		prompt = "Choose an action> ",
		actions = {
			-- @param selected: the selected entry or entries
			["default"] = function(selected)
				local action = selected[1]

				if action == "Edit" then
					vim.cmd("edit " .. file)
				elseif action == "Build" then
					dotnet_build(file)
				elseif action == "Debug" then
					dotnet_debug(file)
				elseif action == "Run" then
					dotnet_run(file)
				end
			end,
		},
	})
end

local function select_project()
	require("fzf-lua").fzf_exec("fd --type f --extension csproj", {
		prompt = "Select a .csproj file> ",
		actions = {
			-- @param selected: the selected entry or entries
			["default"] = function(selected)
				local file = selected[1]

				project_actions(file)
			end,
		},
	})
end

return {
	start_dotnet_actions_by_selecting_project = select_project,
}
