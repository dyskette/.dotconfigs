import { Plugin } from "@opencode/plugin"

// Clones GitHub Copilot's Claude Sonnet 5 / 5.5 into "-1m" variants with a
// 1,000,000 token context limit, and sets the header Copilot requires to
// serve the long-context variant (same trick VS Code / Copilot CLI use).
const VARIANTS = [
  { baseID: "claude-sonnet-5", variantID: "claude-sonnet-5-1m" },
  { baseID: "claude-sonnet-5.5", variantID: "claude-sonnet-5.5-1m" },
] as const

export default Plugin.define({
  id: "copilot-sonnet5-1m",
  async setup(ctx) {
    await ctx.model.transform((editor) => {
      for (const variant of VARIANTS) {
        const source = editor.provider.get("github-copilot")?.models.get(variant.baseID)
        if (!source) continue

        editor.update("github-copilot", variant.variantID, (model) => {
          Object.assign(model, {
            ...source,
            id: variant.variantID,
            name: `${source.name ?? variant.baseID} (1M)`,
            limit: {
              ...(source.limit ?? {}),
              context: 1_000_000,
              output: source.limit?.output ?? 64_000,
            },
          })
        })
      }
    })

    await ctx.session.hook(
      "model.request",
      (event) => {
        event.headers["Copilot-Integration-Id"] = "copilot-developer-cli"
      },
      { providerID: "github-copilot" },
    )
  },
})
