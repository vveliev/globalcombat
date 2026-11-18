# Local dev stack. Ports and subnet are pinned in docker-compose.yml
# (fleet block 11400) — see the comment there before changing anything.

# --remove-orphans drops containers for services no longer in the compose file
# (e.g. the old `mysql` one, which would otherwise keep holding port 11434).
.PHONY: dev
dev:
	docker compose up --build -d --remove-orphans
