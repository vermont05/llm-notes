# LLM Notes

## Model Capability for Macs

https://apxml.com/posts/best-local-llm-apple-silicon-mac

## Self Hosting Coding Tool (ala Claude)

https://www.reddit.com/r/LocalLLaMA/comments/1men28l/guide_the_simple_selfhosted_ai_coding_that_just/

Roo DOES NOT work. It has circular loops inspecting files.
Use Cline instead. No MCP server needed, select Cline profile and it will automatically work.

Clarity: You need both an LLM and a Text Embedding
Ordering issues: Start both models and `Start Server` before turning on MCP Plugin
Size issues: Roo complains unless the models size is increased to 32k
Heat issues: Analyzing codebase is quite intensive. Turn on fan.

## Concepts

### Stable Diffusion vs LLM
https://www.reddit.com/r/MachineLearning/comments/1kenrvr/r_llm_vs_diffusion_models_for_image_generation/

There are notes that LLM -> discrete (ie text) and Diffusion -> continuous (ie images)
