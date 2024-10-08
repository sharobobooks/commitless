# gc - Git Commit Message Generator using OpenAI API
#
# This script automates the generation of git commit messages using the OpenAI API.
# It securely handles API keys, validates user input, and ensures compliance with
# best practices for security and usability.
#
# Installation:
# 1. **Prerequisites**: Ensure you have the required tools installed:
#    - `git`
#    - `curl`
#    - `jq` (You can install `jq` using your package manager, e.g., `sudo apt-get install jq`)
#
# 2. **Save the Script**:
#    - Copy the entire script below.
#    - Paste it into your shell profile configuration file.
#      - For **bash**, add it to `~/.bashrc` or `~/.bash_profile`.
#      - For **zsh**, add it to `~/.zshrc`.
#
# 3. **Set OpenAI API Key**:
#    - Obtain your OpenAI API key from the OpenAI dashboard.
#    - Set it as an environment variable:
#      ```bash
#      export OPENAI_API_KEY='Your-key-here'
#      ```
#    - For permanent access, add the export line to your shell profile file.
#
# Usage:
# - Stage your changes using `git add`.
# - Run `gc` in your terminal.
# - Follow the prompts to generate, review, edit, and confirm your commit message.
#
# Notes:
# - **Data Privacy**: The script will send the git diff of your staged changes to the OpenAI API.
#   Ensure that no sensitive information is included in the diff before proceeding.
# - **Editor Validation**: The script allows certain editors for editing the commit message.
#   Allowed editors are: nano, vim, vi, emacs, code, subl, gedit.
# - **OpenAI Usage Policies**: By using this script, you agree to comply with OpenAI's API usage policies.
# - **Error Handling**: The script includes error handling for network issues, API errors, and user cancellations.
#
# Disclaimer:
# - Use this script at your own risk. Review the generated commit messages and the data being sent to the API.
# - The author is not responsible for any unintended consequences of using this script.

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

    # Load exclusion patterns
    load_exclusions() {
        EXCLUDE_PATTERNS=()
        if [[ -f ".gcignore" ]]; then
            while IFS= read -r line; do
                EXCLUDE_PATTERNS+=("$line")
            done < ".gcignore"
        fi
    }

    # Get filtered git diff
    get_filtered_diff() {
        local exclude_args=()
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            exclude_args+=(":(exclude)$pattern")
        done
        git diff --cached "${exclude_args[@]}"
    }

    # Check if there are staged files
    STAGED_FILES=$(git diff --cached --name-only)
    if [[ -z "$STAGED_FILES" ]]; then
        echo "No files are staged for commit."
        return 1
    fi

    # Load exclusions
    load_exclusions

    # Get the filtered diff of staged files
    GIT_DIFF=$(get_filtered_diff)

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

gcs() {
    # Run the gc function to generate the commit message
    gc_result=$(gc)
    if [[ $? -ne 0 ]]; then
        return 1  # If gc failed, exit
    fi

    # Extract the commit message from the last commit
    COMMIT_MESSAGE=$(git log -1 --pretty=%B)

    # Build the prompt for the security analysis
    SECURITY_PROMPT="Review the following code changes for security vulnerabilities. Provide a structured report with flags and severity rankings for any issues found.\n\nChanges:\n$GIT_DIFF\n\nCommit Message:\n$COMMIT_MESSAGE"

    # Create a JSON payload for the security analysis API request
    SECURITY_PAYLOAD=$(jq -n \
        --arg model "gpt-3.5-turbo" \
        --arg security_prompt "$SECURITY_PROMPT" \
        '{
            model: $model,
            messages: [
                {"role": "user", "content": $security_prompt}
            ],
            max_tokens: 300,
            temperature: 0.3
        }'
    )

    # Call the OpenAI API for security analysis
    HTTP_STATUS=$(curl -s -o security_response.json -w "%{http_code}" https://api.openai.com/v1/chat/completions \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$SECURITY_PAYLOAD"
    )
    SECURITY_RESPONSE=$(cat security_response.json)
    rm -f security_response.json

    if [[ "$HTTP_STATUS" -eq 429 ]]; then
        echo "Error: Rate limit exceeded during security analysis. Please try again later."
        return 1
    elif [[ "$HTTP_STATUS" -ge 400 ]]; then
        echo "Error: Received HTTP status $HTTP_STATUS from OpenAI API during security analysis."
        return 1
    fi

    # Check for API errors
    ERROR_MSG=$(echo "$SECURITY_RESPONSE" | jq -r '.error.message // empty')
    if [[ -n "$ERROR_MSG" ]]; then
        echo "Error from OpenAI API during security analysis: $ERROR_MSG"
        return 1
    fi

    # Extract the security report
    SECURITY_REPORT=$(echo "$SECURITY_RESPONSE" | jq -r '.choices[0].message.content')
    if [[ -z "$SECURITY_REPORT" ]]; then
        echo "Failed to generate security report."
        return 1
    fi

    # Append the security report to the commit message
    UPDATED_COMMIT_MESSAGE="$COMMIT_MESSAGE

Security Analysis:
$SECURITY_REPORT"

    # Allow the user to review the updated commit message
    echo
    echo "Updated commit message with security analysis:"
    echo "-------------------------"
    echo "$UPDATED_COMMIT_MESSAGE"
    echo "-------------------------"
    echo

    # Prompt for user confirmation or editing
    echo "Press 'e' to edit the updated commit message, 'c' to cancel, or any other key to confirm and amend the commit:"
    read -n 1 USER_INPUT
    echo

    case "$USER_INPUT" in
        c)
            echo "Operation canceled."
            return 1
            ;;
        e)
            # Open the updated commit message in the default editor
            TEMP_FILE=$(mktemp)
            trap '[[ -n "$TEMP_FILE" ]] && rm -f "$TEMP_FILE"' EXIT
            echo "$UPDATED_COMMIT_MESSAGE" > "$TEMP_FILE"

            # Validate and use the editor
            if validate_editor; then
                "$EDITOR" "$TEMP_FILE"
            else
                echo "Error: Unauthorized or unset editor. Allowed editors are: ${ALLOWED_EDITORS[*]}"
                echo "Falling back to vi."
                vi "$TEMP_FILE"
            fi

            UPDATED_COMMIT_MESSAGE=$(cat "$TEMP_FILE")
            if [[ -z "$UPDATED_COMMIT_MESSAGE" ]]; then
                echo "Commit message cannot be empty. Operation canceled."
                return 1
            fi
            ;;
    esac

    # Final confirmation before amending the commit
    echo "Do you want to proceed with this updated commit message? (y/N)"
    read -n 1 CONFIRM_COMMIT
    echo
    if [[ ! $CONFIRM_COMMIT =~ ^[Yy]$ ]]; then
        echo "Operation canceled."
        return 1
    fi

    # Amend the last commit with the updated commit message
    COMMIT_MSG_FILE=$(mktemp)
    echo "$UPDATED_COMMIT_MESSAGE" > "$COMMIT_MSG_FILE"
    git commit --amend -F "$COMMIT_MSG_FILE"
    rm -f "$COMMIT_MSG_FILE"

    # Prompt before pushing
    echo "Do you want to push the amended changes? (y/N)"
    read -n 1 REPLY
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git push --force
    else
        echo "Amended changes committed but not pushed."
    fi
}
