vim.filetype.add({
  filename = { [".env"] = "sh" },
  pattern = {
    ["%.env%.[%w_.-]+"] = "sh", -- .env.local, .env.dev
    [".*%.env"] = "sh", -- azure.env, openai.env, ...
  },
})
