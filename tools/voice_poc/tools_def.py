"""The actions voice commands can run (ids match mobile/lib/edit_menu.dart's editCatalog)."""
ACTIONS = {
    "copy": "Copy the selection", "cut": "Cut the selection", "paste": "Paste the clipboard",
    "undo": "Undo the last change", "redo": "Redo", "select_all": "Select everything",
    "find": "Search in the page or document", "save": "Save the file",
    "enter": "Press the Enter key", "backspace": "Delete the character before the cursor",
    "delete": "Delete the character after the cursor", "escape": "Press Escape",
    "tab": "Press Tab", "refresh": "Reload the page", "open_terminal": "Open a terminal window",
    "close_app": "Close the focused window or application", "new_tab": "Open a new browser tab",
    "close_tab": "Close the current browser tab", "page_up": "Page up", "page_down": "Page down",
    "home": "Go to the start of the line", "end": "Go to the end of the line",
}
TOOLS = [
    {"name": "key_action", "description": "Press an editing or navigation shortcut on the computer.",
     "parameters": {"type": "object", "properties": {
         "action": {"type": "string", "enum": sorted(ACTIONS), "description": "; ".join(f"{k}: {v}" for k, v in ACTIONS.items())},
         "times": {"type": "integer", "description": "How many times, default 1"}}, "required": ["action"]}},
    {"name": "scroll", "description": "Scroll the page.",
     "parameters": {"type": "object", "properties": {
         "direction": {"type": "string", "enum": ["up", "down"]},
         "amount": {"type": "string", "enum": ["little", "page", "far"], "description": "how far"}}, "required": ["direction"]}},
    {"name": "volume", "description": "Change the computer's sound volume.",
     "parameters": {"type": "object", "properties": {
         "change": {"type": "string", "enum": ["up", "down", "mute"]}}, "required": ["change"]}},
    {"name": "mouse_click", "description": "Click the mouse.",
     "parameters": {"type": "object", "properties": {
         "button": {"type": "string", "enum": ["left", "right", "middle"]},
         "double": {"type": "boolean"}}, "required": ["button"]}},
]
