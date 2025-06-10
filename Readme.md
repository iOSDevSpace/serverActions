# iOS Dev Space Server Scripts

This repository houses automated scripts for iOS Dev Space server administration and maintenance tasks.

## Scripts

### WelcomeBot

A Swift script that automatically sends welcome direct messages to newly approved users on the iOS Dev Space Mastodon instance.

**How it works:**
- Checks for accounts created since the last run that have been approved
- Sends a personalized welcome DM to each new iOS Dev Space member
- Updates a timestamp file to track progress
- Runs automatically 3 times daily via GitHub Actions (8am, 2pm, 8pm UTC)

**Requirements:**
- Admin access to the iOS Dev Space Mastodon instance
- Mastodon API credentials (access token)

## Running Locally

### WelcomeBot

1. **Create a `.env` file in the repository root:**
   ```
   MASTODON_BASE_URL=https://iosdev.space
   MASTODON_ACCESS_TOKEN=your-access-token
   ```

2. **Run the script:**
   ```bash
   chmod +x WelcomeBot.swift
   swift WelcomeBot.swift
   ```

The script will:
- Read the last check timestamp from `last_check_timestamp.txt`
- Process new approved users
- Update the timestamp file after each successful message

## Adding New Scripts

When adding new iOS Dev Space automation scripts to this repository:
1. Create the script file in the root directory
2. Add a corresponding GitHub Actions workflow in `.github/workflows/`
3. Update this README with documentation for the new script
4. Add any required secrets to the repository settings
