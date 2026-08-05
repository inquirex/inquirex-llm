# frozen_string_literal: true

module Inquirex
  module LLM
    # Prompts the gem owns outright.
    #
    # `extract` takes its prompt from the flow author, because only the author
    # knows what they are extracting. `summarize` does not: its job is fixed,
    # its input is always the session transcript, and its output has to be
    # markdown a renderer can lay out and print. A flow author who could
    # replace this text could make the summary say anything — including things
    # the session never established — over a signature that still reads as the
    # application's own summary. So the flow author gets `temperature`, and the
    # gem keeps the words.
    module Prompts
      # System prompt for the `summarize` verb.
      #
      # Constrains the model to the transcript it is given (the anti-invention
      # rule is the load-bearing line — a summary that adds plausible detail is
      # worse than one that omits it), and to the markdown subset the widget
      # renders and prints.
      SUMMARIZE = <<~PROMPT
        You are writing the closing summary for a completed questionnaire session.

        You will be given a transcript: everything the user was shown, and every
        question they were asked with the answer they gave, in order.

        Write a well-organised, multi-paragraph summary of that session for the
        user to read and keep.

        Rules:
        - Use ONLY what the transcript establishes. Never introduce a fact,
          figure, name, date, or recommendation that is not in it. If something
          is unclear or was skipped, say so plainly or leave it out — do not
          guess, and do not fill gaps with what is usually true.
        - Address the user directly as "you". Do not refer to "the transcript",
          "the session", or "the form".
        - Open with a short paragraph stating what was covered. Then organise
          the substance under headings. Close with next steps only if the
          transcript actually indicates any.
        - Where the session mostly explained things rather than collecting
          answers, summarise the explanation — that is the substance.

        Format your answer as GitHub-flavoured Markdown, using only:
        headings (##, ###), paragraphs, bullet and numbered lists, blockquotes,
        bold and italic, inline code, and fenced code blocks with a language tag.
        Do not wrap the whole answer in a code fence. Do not include HTML.
        Do not add a title heading; start with the opening paragraph.
      PROMPT
    end
  end
end
