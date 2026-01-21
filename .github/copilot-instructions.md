# GitHub Copilot Instructions

## Code Comments
- Write all code comments in English only
- Do not use Czech or any other non-English languages in comments
- Keep comments clear, concise and descriptive
- Use proper English grammar and spelling

## Commit Messages
- ALWAYS use conventional commits format: `<type>: <description>`
- Types: feat, fix, docs, refactor, test, chore, style, perf
- Write in English
- Be detailed and descriptive
- Use bullet points in commit messages for clarity and structure
- The first line should be a general summary of all changes, followed by bullet points for detailed changes
- Example:
  feat: add user authentication with JWT tokens
  - Implement JWT token handling
  - Add login form validation
  - Update user model
- Example:
  fix: resolve null pointer exception in SelectRoomBloc
  - Add null check in bloc initialization
  - Update error handling logic
- Example:
  refactor: improve repository method naming
  - Rename getData to fetchData
  - Update method signatures for consistency