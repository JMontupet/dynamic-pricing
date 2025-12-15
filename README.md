# Pricing Service

## Overview

This service exposes a simple HTTP API that returns a room price based on a **period**, **hotel**, and **room**. It acts as a proxy layer in front of the external pricing model.


## API Documentation

### `GET /pricing`

**Query parameters**:

* `period` (string, required)
* `hotel` (string, required)
* `room` (string, required)

**Successful response (200)**

```json
{
  "rate": "12000"
}
```

**Error response (4xx / 5xx)**

```json
{
  "error": "Descriptive error message"
}
```

Errors are returned when:

* Required parameters are missing or invalid
* The pricing model returns an error
* The pricing model returns an invalid response
* The pricing model is unreachable or times out
* The pricing model quota exceed


## Implementation Details

### Architecture

* **Controller**

  * Validates input parameters
  * Maps domain errors to HTTP responses

* **Cache**

  * Implemented as an in-memory cache
  * Uses a hard TTL aligned with the 5 minute rate validity constraint
  * Uses a soft TTL to proactively refresh frequently accessed entries
  * When a cached entry is soft-expired but still valid, the service:
    * Serves the cached value immediately
    * Triggers a background refresh with retry
  * Circuit breaker:
    * Tracks recent failures when calling the pricing model
    * Temporarily short-circuits requests after a failure threshold is reached
    * Automatically recovers after a cool-down period


* **Pricing Model Client**

  * Encapsulates all communication with the external pricing model
  * Uses Faraday and Faraday Retry
  * Applies strict timeouts to avoid request pile-ups
  * Retries on http error (500)
  * Validates and normalizes responses

## Possible Improvements

Given more time, the following enhancements could be done:


* **Batching:**
Aggregate multiple pricing requests into batched calls to the pricing model to reduce request volume and cost.

* **Logging & Monitoring:**
Add structured logging and metrics (latency, error rates, retries, circuit breaker state). Must have before doing any other improvement.

* **Distributed Cache (Redis):**
Replace the in-memory cache with Redis to share cached rates across instances.

* **Consistent Hashing Load Balancing:**
When running multiple instances, use consistent hashing to route identical pricing keys to the same instance, improving cache locality and reducing duplicate calls to the pricing model.


## Pricing Model API Improvements

* Avoid returning HTTP 200 responses for error cases
* Guarantee presence and format of the rate field
* Enforce request timeouts to prevent hanging calls
* Standardize error responses and status codes


## Running the Service

```bash

# --- 1. Build & Run The Main Application ---
PRICING_MODEL_TOKEN=<YOUR_VALID_TOKEN> docker compose up

# --- 2. Test The Endpoint ---
# Send a sample request to your running service
curl 'http://localhost:3000/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'

```


