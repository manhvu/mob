defmodule Dala.Preview.Live.Layout do
  @moduledoc """
  Layout module for Dala Preview LiveView.

  This layout wraps the preview in a minimal HTML structure
  with the necessary JavaScript and CSS for interactivity.
  """

  # This is a simple layout module that returns HTML
  # It doesn't use Phoenix.LiveView.Layout to avoid compilation issues

  @doc """
  Render the layout.
  """
  def render(assigns) do
    title = assigns[:page_title] || "Dala Preview"
    inner_content = assigns[:inner_content] || ""

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
        <title>#{title}</title>

        <script src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js" defer></script>

        <style>
          :root {
            --primary: #2196F3;
            --surface: #FFFFFF;
            --on-surface: #212121;
            --background: #F5F5F5;
            --border: #E0E0E0;
            --space-xs: 4px;
            --space-sm: 8px;
            --space-md: 16px;
            --space-lg: 24px;
          }

          body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            margin: 0;
            padding: var(--space-md);
            background: var(--background);
            color: var(--on-surface);
          }

          .live-preview-container {
            display: flex;
            gap: var(--space-lg);
            max-width: 1600px;
            margin: 0 auto;
          }

          .preview-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: var(--space-md);
            padding-bottom: var(--space-md);
            border-bottom: 1px solid var(--border);
          }

          .preview-header h2 {
            margin: 0;
          }

          .preview-header button {
            background: var(--primary);
            color: white;
            border: none;
            padding: var(--space-sm) var(--space-md);
            border-radius: 4px;
            cursor: pointer;
          }

          .preview-content {
            flex: 1;
            max-width: 800px;
          }

          .event-log {
            flex: 1;
            max-width: 400px;
            padding: var(--space-md);
            background: #F9F9F9;
            border-radius: 8px;
            border: 1px solid var(--border);
            max-height: 600px;
            overflow-y: auto;
          }

          .event-log h3 {
            margin-top: 0;
            margin-bottom: var(--space-sm);
          }

          .log-entry {
            padding: 4px;
            border-bottom: 1px solid var(--border);
            font-family: monospace;
            font-size: 12px;
          }

          .log-entry strong {
            margin-right: 8px;
          }
        </style>
      </head>
      <body>
        #{inner_content}
      </body>
    </html>
    """
  end
end
