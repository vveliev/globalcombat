# Local dev stack. Ports and subnet are pinned in docker-compose.yml
# (fleet block 11400) — see the comment there before changing anything.

.PHONY: dev
dev:
	docker compose up --build -d
