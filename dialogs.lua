local InputDialog = require("ui/widget/inputdialog")
local ChatGPTViewer = require("chatgptviewer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

local queryChatGPT = require("gpt_query")

local CONFIGURATION = nil
local buttons, input_dialog

local success, result = pcall(function()
	return require("configuration")
end)
if success then
	CONFIGURATION = result
else
	print("configuration.lua not found, skipping...")
end

local function translateText(text, target_language)
	local translation_message = {
		role = "user",
		content = "你是个具各个领域的天才专家， 你擅长按照原本的文字意思使用习惯翻译成中文，忽略原文中错误的用法，使用更加专业的文字翻译，翻译结果全部使用中文，翻译后的结果除了专有名词，不要有英文，并且很好的使用中文的语法特性已经中文用语习惯，如果有错误的英语表达，根据前后文推测并给出中文结果，翻译结果必须做到“信、达、雅”，不要做任何解释说明，直接给出翻译后的内容，帮我翻译: "
			.. target_language
			.. ": "
			.. text,
	}
	local translation_history = {
		{
			role = "system",
			content = "You are a helpful translation assistant. Provide direct translations without additional commentary.",
		},
		translation_message,
	}
	return queryChatGPT(translation_history)
end

local function callLLM(input_text, prompt, system)
	local translation_message = {
		role = "user",
		content = prompt
			.. ":"
			.. input_text,
	}
	local translation_history = {
		{
			role = "system",
			content = system,
		},
		translation_message,
	}
	return queryChatGPT(translation_history)
end

local function createResultText(highlightedText, message_history)
	local result_text = _("Highlighted text: ") .. '"' .. highlightedText .. '"\n\n'

	for i = 3, #message_history do
		if message_history[i].role == "user" then
			result_text = result_text .. _("User: ") .. message_history[i].content .. "\n\n"
		else
			result_text = result_text .. _("ChatGPT: ") .. message_history[i].content .. "\n\n"
		end
	end

	return result_text
end

local function showLoadingDialog()
	local loading = InfoMessage:new({
		text = _("Loading..."),
		timeout = 0.1,
	})
	UIManager:show(loading)
end

local function showChatGPTDialog(ui, highlightedText, message_history)
	local title, author =
		ui.document:getProps().title or _("Unknown Title"), ui.document:getProps().authors or _("Unknown Author")
	local message_history = message_history
		or {
			{
				role = "system",
				content = "The following is a conversation with an AI assistant. The assistant is helpful, creative, clever, and very friendly. Answer as concisely as possible.",
			},
		}

	local function handleNewQuestion(chatgpt_viewer, question)
		table.insert(message_history, {
			role = "user",
			content = question,
		})

		local answer = queryChatGPT(message_history)

		table.insert(message_history, {
			role = "assistant",
			content = answer,
		})

		local result_text = createResultText(highlightedText, message_history)

		chatgpt_viewer:update(result_text)
	end

	buttons = {
		{
			text = _("Cancel"),
			callback = function()
				UIManager:close(input_dialog)
			end,
		},
		{
			text = _("Ask"),
			callback = function()
				local question = input_dialog:getInputText()
				UIManager:close(input_dialog)
				showLoadingDialog()

				UIManager:scheduleIn(0.1, function()
					local context_message = {
						role = "user",
						content = "I'm reading something titled '"
							.. title
							.. "' by "
							.. author
							.. ". I have a question about the following highlighted text: "
							.. highlightedText,
					}
					table.insert(message_history, context_message)

					local question_message = {
						role = "user",
						content = question,
					}
					table.insert(message_history, question_message)

					local answer = queryChatGPT(message_history)
					local answer_message = {
						role = "assistant",
						content = answer,
					}
					table.insert(message_history, answer_message)

					local result_text = createResultText(highlightedText, message_history)

					local chatgpt_viewer = ChatGPTViewer:new({
						title = _("AskGPT"),
						text = result_text,
						onAskQuestion = handleNewQuestion,
					})

					UIManager:show(chatgpt_viewer)
				end)
			end,
		},
	}

	if CONFIGURATION and CONFIGURATION.features and CONFIGURATION.features.translate_to then
		table.insert(buttons, {
			text = _("Translate"),
			callback = function()
				showLoadingDialog()

				UIManager:scheduleIn(0.1, function()
					local translated_text = translateText(highlightedText, CONFIGURATION.features.translate_to)

					table.insert(message_history, {
						role = "user",
						content = "Translate to " .. CONFIGURATION.features.translate_to .. ": " .. highlightedText,
					})

					table.insert(message_history, {
						role = "assistant",
						content = translated_text,
					})

					local result_text = createResultText(highlightedText, message_history)
					local chatgpt_viewer = ChatGPTViewer:new({
						title = _("Translation"),
						text = result_text,
						onAskQuestion = handleNewQuestion,
					})

					UIManager:show(chatgpt_viewer)
				end)
			end,
		})
	end

	if CONFIGURATION and CONFIGURATION.features and CONFIGURATION.features.dictionary then
		table.insert(buttons, {
			text = _("Custom"),
			callback = function()
				showLoadingDialog()

				UIManager:scheduleIn(0.1, function()
					local translated_text = callLLM(highlightedText, CONFIGURATION.features.dictionary.prompt, CONFIGURATION.features.dictionary.system)

					table.insert(message_history, {
						role = "user",
						content = "Search " .. CONFIGURATION.features.dictionary.name .. ": " .. highlightedText,
					})

					table.insert(message_history, {
						role = "assistant",
						content = translated_text,
					})

					local result_text = createResultText(highlightedText, message_history)
					local chatgpt_viewer = ChatGPTViewer:new({
						title = _("Custom"),
						text = result_text,
						onAskQuestion = handleNewQuestion,
					})

					UIManager:show(chatgpt_viewer)
				end)
			end,
		})
	end

	input_dialog = InputDialog:new({
		title = _("Ask a question about the highlighted text"),
		input_hint = _("Type your question here..."),
		input_type = "text",
		buttons = { buttons },
	})
	UIManager:show(input_dialog)
end

return showChatGPTDialog

