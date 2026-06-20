APPLICATIONAME = bank-app-parser

SPECIFICATION

# Main goal
This is an application that stores and analyzes my bank transactions to optimize my personal finances.
It ingests the transactions through screenshots of me browsing my banks mobile apps and using gemini
to parse those videos and images.

## High level Implementation

* First implement the endpoint(POST /ingest) that accepts images.
 That endpoint process them in a background job.
( Uses a hardcoded in the env token for authentication.


### Preprocessing
* Processing includes resizing images so that the width and the height are less than 768 (keeping the image's aspect ratio)
* It should transform the images to greyscale.
* The images will be a series of screenshots of me scrolling through a list of transactions,
    use https://github.com/nocoo/image-stitch to stich them together as part of the preprocessing.
    run it calling it with Open3.popen2e

* asume image magick is available.

### OCR
After processing, send the images to Gemini with gpt-5.4-nano with this prompt 

You are an expert data extraction assistant. Your task is to analyze the provided screenshot of bank transactions
and extract all line items into a clean, structured format.

```
### Instructions:
1. Extract every unique transaction visible in the image.
2. De-duplicate: The image may show the same transaction multiple times. Only record each unique transaction once.
3. If a transaction is partially cut off at the very beginning or end of image video and the details are illegible, omit it.
4. Convert all shorthand month names to standard full dates if the year is known (e.g., "Oct 12" -> "2025-10-12"). If the year is not visible, default to the current year 2026.

### Output Format:
Provide the output strictly as a valid JSON array of objects (which I will convert to CSV). Do not include any conversational text, markdown formatting blocks (like ```json), or explanations.
- "date": YYYY-MM-DD format
- "description": The text description or vendor name
- "bank_name": infer the name of the bank from the UI, if not sure output 'unknown'
- "merchant": the name of the merchant if available otherwise 'unknown'
- "cardname": infer the name of the credit card from the UI, if not sure output 'unknown'
- "amount": The amount as a float (negative for expenditures/debits, positive for income/credits)
- "category": A best-guess category based on the vendor name (e.g., Food, Utilities, Transport, Shopping)
```


### Post-OCR
After OCRing create the transactions

### UI

On the root of the app / display the following data

1. Top Heavy Categories (Pie Chart Ready): Aggregate the total spend by category. What are the top 3 to 5 categories that consume the highest percentage of the total budget? Include the total amount and the percentage of overall spend for each.
2. Top Merchants (Bar Chart Ready): Regardless of category, which 5 specific merchants, stores, or vendors received the most money overall?
3. Largest Single Purchases (List Ready): What were the top 5 most expensive individual transactions in this dataset? Include the date, merchant, and amount.
4. Timeseries of spending per category (in columns with colors)

* No authentication in this endpoint for now

### Core Environment & Versioning

- **Application Name:** `APPLICATIONNAME`
    
- **Ruby Version:** Use **Ruby 3.4.7** (managed via `rbenv`).
    
- **Configuration Files:**
    
    - Create a `.ruby-version` file specifying `3.4.7`.
        
    - Hardcode the Ruby version within the `Gemfile`.
        
- **Git Configuration:** Provide a robust `.gitignore` including defaults for macOS (`.DS_Store`), Rails `tmp/` folders, `log/` files, environment variables, and rails credentials and keys for encryption
    

### Database & Storage Architecture

- **Engine:** PostgreSQL.
    
- **Database Provisioning:** Initialize three standard environments:
    
    - `APPLICATIONNAME_production`
        
    - `APPLICATIONNAME_development`
        
    - `APPLICATIONNAME_test`
        
- **Unified Schema:** Utilize a single database schema for all application data.
    
- **Postgres-Backed Services:**
    
    - **Cache:** Configure Rails to use PostgreSQL as the cache store.
        
    - **Active Job:** Configure the background job queue to run through PostgreSQL (e.g., using `solid_queue`).
        
    - **Schema Integration:** Ensure all cache and job-related tables are included in the primary database schema.
        

### Testing & Reliability

- **Testing Framework:** Replace default Minitest with **RSpec**.
    
- **Health Monitoring:**
    
    - Implement a `/health` endpoint managed by a dedicated controller.
        
    - **Logic:** Return a `200 OK` status only if all dependencies are operational.
        
    - **Checks:** Verify the database connection, and validate any attached services.

## Libraries

* Dotenv
* Install the https://github.com/httprb/http gem when we need to call a third party with a custom client.
* Use the gem inertia rails for all views
* Tailwind for all styling
* https://www.chartjs.org/ for rendering 

## Developer experience

* Configure vite to build the assets and autoreload on development when a file changes
* Make sure tailwind classes regeneration is also configured
* Ensure the active jobs output goes to STDOUT in development
* To make easy to debug the image processing pipeline add debugging comments every major step

Add a ./serve-dev file to run the server and related in development use tmx sessions
```
#!/bin/bash

# Load environment variables
set -a
[ -f .env ] && . .env
set +a

rails assets:precompile

SESSION="APPLICATIONNAME"

# Kill existing session if any
tmux kill-session -t "$SESSION" 2>/dev/null

# Create session with first pane: Rails
tmux new-session -d -s "$SESSION" -n main

# Split into 3 panes
tmux split-window -h -t "$SESSION"
tmux split-window -v -t "$SESSION"

# Pane 1: Rails server
tmux send-keys -t "$SESSION:main.1" "source .env && be rails s -p $RAILS_PORT -b 0.0.0.0" C-m

# Pane 2: Solid Queue worker
tmux send-keys -t "$SESSION:main.2" "source .env && RAILS_LOG_TO_STDOUT=1 bundle exec rake solid_queue:start" C-m

# Attach to session
tmux attach -t "$SESSION"
```

## Documentation

Add a README.md that explains the purpose of the project the architecture and how to run it and install it. 


## AGENTS

Add claude.md after building the app.
Include in the instructions



