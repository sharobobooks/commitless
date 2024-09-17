Commitless
Automate your Git commit messages using the OpenAI API.

Commitless is a Bash script that generates concise and effective Git commit messages by analyzing your staged changes and leveraging the OpenAI API. It enhances your workflow by automating the commit message creation process while ensuring best practices for security and usability.

Features
Automated Commit Messages: Generates commit messages based on your staged changes.
User Interaction: Allows you to review, edit, or cancel the commit message before committing.
Security Considerations: Includes warnings about sensitive data and validates editors.
Error Handling: Provides comprehensive error handling for network issues, API errors, and user cancellations.
Table of Contents
Installation
Usage
Configuration
Notes
Contributing
License
Disclaimer
Installation
Prerequisites
Ensure you have the following tools installed:

Git

curl

jq: You can install jq using your package manager:

bash
Copy code
# For Debian/Ubuntu
sudo apt-get install jq

# For macOS using Homebrew
brew install jq
Install the Script
Clone the Repository

bash
Copy code
git clone https://github.com/yourusername/commitless.git
Add the Script to Your Shell Profile

Copy the gc function from the commitless.sh file and paste it into your shell profile configuration file.

For Bash: Add it to ~/.bashrc or ~/.bash_profile.
For Zsh: Add it to ~/.zshrc.
bash
Copy code
# Open your shell profile in an editor
nano ~/.bashrc

# Paste the gc function at the end of the file
# [Paste the script here]

# Save and exit the editor
Reload Your Shell Profile

bash
Copy code
source ~/.bashrc
Usage
Set Your OpenAI API Key

Obtain your OpenAI API key from the OpenAI Dashboard and set it as an environment variable:

bash
Copy code
export OPENAI_API_KEY='your-api-key-here'
To make this change permanent, add the export line to your shell profile file.
Stage Your Changes

Use Git to stage the changes you want to commit:

bash
Copy code
git add .
Run the gc Command

bash
Copy code
gc
Follow the Prompts

Review the Diff: Optionally review the diff to ensure no sensitive data is included.
Generate Commit Message: The script will generate a commit message using the OpenAI API.
Edit or Confirm: You can edit the commit message, cancel, or proceed with the commit.
Push Changes: After committing, choose whether to push the changes to the remote repository.
Configuration
Set Your Preferred Editor
The script allows certain editors for editing the commit message. Allowed editors are:

nano
vim
vi
emacs
code (Visual Studio Code)
subl (Sublime Text)
gedit
Set your preferred editor by exporting the EDITOR environment variable:

bash
Copy code
export EDITOR='nano'
Add this line to your shell profile to make it permanent.

Exclude Sensitive Files
Create a .gcignore file in your repository to exclude certain files or patterns from the git diff sent to the OpenAI API.

Example .gcignore content:

bash
Copy code
*.env
config/secret.json
Notes
Data Privacy: The script will send the git diff of your staged changes to the OpenAI API. Ensure that no sensitive information is included in the diff before proceeding.
OpenAI Usage Policies: By using this script, you agree to comply with OpenAI's API usage policies.
Rate Limits: Be mindful of the OpenAI API rate limits and usage quotas associated with your account.
Contributing
Contributions are welcome! Please follow these steps:

Fork the Repository

Click the "Fork" button at the top right of the repository page.

Clone Your Fork

bash
Copy code
git clone https://github.com/yourusername/commitless.git
Create a New Branch

bash
Copy code
git checkout -b feature/your-feature-name
Make Your Changes

Commit and Push

bash
Copy code
git add .
git commit -m "Add your commit message here"
git push origin feature/your-feature-name
Submit a Pull Request

Go to the original repository and click on "New Pull Request".

License
This project is licensed under the MIT License.

Disclaimer
Use this script at your own risk. Review the generated commit messages and the data being sent to the API.
The author is not responsible for any unintended consequences of using this script.
Ensure compliance with your organization's policies regarding the use of third-party APIs and the handling of sensitive data.
The gc Function Script
bash
Copy code
gc() {
    # Ensure required commands are installed
    for cmd in git curl jq; do
        if ! command -v $cmd &> /dev/null; then
            echo "Error: Required command '$cmd' is not installed."
            return 1
        fi
    done

    # Allowed editors
    ALLOWED_EDITORS=("nano" "vim" "vi" "emacs" "code" "subl" "gedit")

    # Function to validate the editor
    validate_editor() {
        if [[ -z "$EDITOR" ]]; then
            return 1  # EDITOR is not set
        fi
        local editor_cmd=$(basename "$EDITOR")
        for allowed in "${ALLOWED_EDITORS[@]}"; do
            if [[ "$editor_cmd" == "$allowed" ]]; then
                return 0  # Editor is allowed
            fi
        done
        return 1  # Editor is not in the allowed list
    }

    # Check if there are staged files
    STAGED_FILES=$(git diff --cached --name-only)
    if [[ -z "$STAGED_FILES" ]]; then
        echo "No files are staged for commit."
        return 1
    fi

    # Get the diff of staged files
    GIT_DIFF=$(git diff --cached)

    # Limit the size of the git diff
    MAX_DIFF_SIZE=8000
    if [[ ${#GIT_DIFF} -gt $MAX_DIFF_SIZE ]]; then
        echo "Git diff is too large; truncating to $MAX_DIFF_SIZE characters."
        GIT_DIFF="${GIT_DIFF:0:$MAX_DIFF_SIZE}"
    fi

    # Warning about potential sensitive data
    echo "WARNING: This script will send your git diff to OpenAI API. Ensure no sensitive data is included."
    echo "Would you like to review the diff before sending? (y/N)"
    read -n 1 REVIEW_DIFF
    echo
    if [[ $REVIEW_DIFF =~ ^[Yy]$ ]]; then
        git diff --cached
        echo "Proceed with sending this diff to OpenAI? (y/N)"
        read -n 1 PROCEED
        echo
        if [[ ! $PROCEED =~ ^[Yy]$ ]]; then
            echo "Operation canceled."
            return 1
        fi
    fi

    # Build the prompt for the OpenAI API
    SYSTEM_PROMPT="You are a helpful assistant that writes concise and effective git commit messages."
    USER_PROMPT="Generate a concise git commit message for the following changes:\n\n$GIT_DIFF"

    # Create a JSON payload for the API request
    JSON_PAYLOAD=$(jq -n \
        --arg model "gpt-3.5-turbo" \
        --arg system_prompt "$SYSTEM_PROMPT" \
        --arg user_prompt "$USER_PROMPT" \
        '{
            model: $model,
            messages: [
                {"role": "system", "content": $system_prompt},
                {"role": "user", "content": $user_prompt}
            ],
            max_tokens: 100,
            temperature: 0.5
        }'
    )

    # Call the OpenAI API
    HTTP_STATUS=$(curl -s -o response.json -w "%{http_code}" https://api.openai.com/v1/chat/completions \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$JSON_PAYLOAD"
    )
    RESPONSE=$(cat response.json)
    rm -f response.json

    if [[ "$HTTP_STATUS" -eq 429 ]]; then
        echo "Error: Rate limit exceeded. Please try again later."
        return 1
    elif [[ "$HTTP_STATUS" -ge 400 ]]; then
        echo "Error: Received HTTP status $HTTP_STATUS from OpenAI API."
        return 1
    fi

    # Check for API errors
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error.message // empty')
    if [[ -n "$ERROR_MSG" ]]; then
        echo "Error from OpenAI API: $ERROR_MSG"
        return 1
    fi

    # Extract the commit message
    COMMIT_MESSAGE=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
    if [[ -z "$COMMIT_MESSAGE" ]]; then
        echo "Failed to generate commit message."
        return 1
    fi

    # Display the commit message and staged files
    echo
    echo "Generated commit message:"
    echo "-------------------------"
    echo "$COMMIT_MESSAGE"
    echo "-------------------------"
    echo
    echo "Staged files:"
    echo "-------------------------"
    echo "$STAGED_FILES"
    echo "-------------------------"
    echo

    # Prompt for user confirmation or editing
    echo "Press 'e' to edit the commit message, 'c' to cancel, or any other key to confirm and commit:"
    read -n 1 USER_INPUT
    echo

    case "$USER_INPUT" in
        c)
            echo "Commit canceled."
            return 1
            ;;
        e)
            # Open the commit message in the default editor
            TEMP_FILE=$(mktemp)
            trap '[[ -n "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"' EXIT
            echo "$COMMIT_MESSAGE" > "$TEMP_FILE"
            
            # Validate and use the editor
            if validate_editor; then
                "$EDITOR" "$TEMP_FILE"
            else
                echo "Error: Unauthorized or unset editor. Allowed editors are: ${ALLOWED_EDITORS[*]}"
                echo "Falling back to vi."
                vi "$TEMP_FILE"
            fi
            
            COMMIT_MESSAGE=$(cat "$TEMP_FILE")
            if [[ -z "$COMMIT_MESSAGE" ]]; then
                echo "Commit message cannot be empty. Commit canceled."
                return 1
            fi
            ;;
    esac

    # Final confirmation before committing
    echo "Do you want to proceed with this commit message? (y/N)"
    read -n 1 CONFIRM_COMMIT
    echo
    if [[ ! $CONFIRM_COMMIT =~ ^[Yy]$ ]]; then
        echo "Commit canceled."
        return 1
    fi

    # Commit the changes
    COMMIT_MSG_FILE=$(mktemp)
    echo "$COMMIT_MESSAGE" > "$COMMIT_MSG_FILE"
    git commit -F "$COMMIT_MSG_FILE"
    rm -f "$COMMIT_MSG_FILE"

    # Prompt before pushing
    echo "Do you want to push the changes? (y/N)"
    read -n 1 REPLY
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git push
    else
        echo "Changes committed but not pushed."
    fi
}
Enjoy using Commitless to automate your Git commit messages!
