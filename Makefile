# ─────────────────────────────────────────────────────────────────────────────
# dbtggsql-demo · Makefile
#
# Usage:
#   make                   → build + quarto report (Option A, default)
#   OUTPUT=cli   make      → build + individual ggsql CLI charts (Option B)
#   OUTPUT=static make     → build + static HTML bundle with index (Option C)
#   make build             → dbt pipeline only (no output)
#   make install-cli       → install ggsql CLI via cargo
#
# Environment variables:
#   OUTPUT        quarto | cli | static   (default: quarto)
#   RUN_DBT       if set, the QMD's bash cell also runs dbt (for Connect)
#   NBA_TEAM      optional team filter passed through to ggsql getenv()
# ─────────────────────────────────────────────────────────────────────────────

OUTPUT       ?= quarto
DBT_DIR      := nba_dbt
ANALYSES_DIR := analyses
OUTPUT_DIR   := output
GGSQL        := ggsql

.PHONY: all build quarto cli static install-cli clean help

# ── Default target ────────────────────────────────────────────────────────────
all: build $(OUTPUT)

# ── dbt pipeline (shared across all output types) ─────────────────────────────
build:
	@echo "▶  Running dbt pipeline..."
	cd $(DBT_DIR) && uv run dbt build --profiles-dir . --project-dir .
	@echo "✓  dbt build complete — parquet exports updated"

# ── Option A: Full Quarto report ──────────────────────────────────────────────
quarto:
	@echo "▶  Rendering Quarto report (Option A)..."
	quarto render nba_report.qmd
	@echo "✓  Report → nba_report.html"

# ── Option B: Individual ggsql CLI charts ─────────────────────────────────────
# ggsql CLI outputs raw Vega-Lite JSON — we wrap it in a self-contained HTML
# page that loads Vega-Lite from CDN and renders the chart at a fixed size.
cli: _check-ggsql
	@echo "▶  Rendering individual ggsql charts (Option B)..."
	@mkdir -p $(OUTPUT_DIR)/charts
	@for f in $(ANALYSES_DIR)/*.ggsql; do \
		name=$$(basename $$f .ggsql); \
		echo "   rendering $$name..."; \
		spec=$$($(GGSQL) run "$$f" --reader duckdb://memory 2>/dev/null); \
		printf '<!DOCTYPE html><html><head><meta charset="utf-8"/><title>%s</title>\n' "$$name" > $(OUTPUT_DIR)/charts/$$name.html; \
		printf '<script src="https://cdn.jsdelivr.net/npm/vega@5"></script>\n' >> $(OUTPUT_DIR)/charts/$$name.html; \
		printf '<script src="https://cdn.jsdelivr.net/npm/vega-lite@6"></script>\n' >> $(OUTPUT_DIR)/charts/$$name.html; \
		printf '<script src="https://cdn.jsdelivr.net/npm/vega-embed@6"></script>\n' >> $(OUTPUT_DIR)/charts/$$name.html; \
		printf '<style>*{box-sizing:border-box;margin:0;padding:0}body{background:#f8fafc;display:flex;justify-content:center;align-items:center;min-height:100vh}#vis{background:white;border-radius:8px;box-shadow:0 2px 12px #0000001a;padding:24px;width:860px;height:620px}</style>\n' >> $(OUTPUT_DIR)/charts/$$name.html; \
		printf '</head><body><div id="vis"></div><script>\n' >> $(OUTPUT_DIR)/charts/$$name.html; \
		printf 'const spec = %s;\nspec.width=800;spec.height=560;\n' "$$spec" >> $(OUTPUT_DIR)/charts/$$name.html; \
		printf 'vegaEmbed("#vis",spec,{actions:false,renderer:"svg"}).catch(console.error);\n' >> $(OUTPUT_DIR)/charts/$$name.html; \
		printf '</script></body></html>\n' >> $(OUTPUT_DIR)/charts/$$name.html; \
	done
	@echo "✓  Charts → $(OUTPUT_DIR)/charts/"

# ── Option C: Static bundle (charts + index page) ─────────────────────────────
static: cli
	@echo "▶  Assembling static index (Option C)..."
	@mkdir -p $(OUTPUT_DIR)/static
	@cp $(OUTPUT_DIR)/charts/*.html $(OUTPUT_DIR)/static/
	@echo '<!DOCTYPE html>' > $(OUTPUT_DIR)/static/index.html
	@echo '<html><head><meta charset="utf-8">' >> $(OUTPUT_DIR)/static/index.html
	@echo '<title>2026 NBA Finals · ggsql Charts</title>' >> $(OUTPUT_DIR)/static/index.html
	@echo '<style>' >> $(OUTPUT_DIR)/static/index.html
	@echo '  body{font-family:system-ui,sans-serif;max-width:900px;margin:40px auto;padding:0 20px;color:#1e293b}' >> $(OUTPUT_DIR)/static/index.html
	@echo '  h1{font-size:1.6rem;margin-bottom:4px} p{color:#64748b;margin-top:0}' >> $(OUTPUT_DIR)/static/index.html
	@echo '  ul{list-style:none;padding:0;display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:24px}' >> $(OUTPUT_DIR)/static/index.html
	@echo '  li a{display:block;padding:12px 16px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;' >> $(OUTPUT_DIR)/static/index.html
	@echo '       text-decoration:none;color:#1e293b;font-size:.9rem;transition:background .15s}' >> $(OUTPUT_DIR)/static/index.html
	@echo '  li a:hover{background:#eff6ff;border-color:#93c5fd}' >> $(OUTPUT_DIR)/static/index.html
	@echo '  footer{margin-top:40px;font-size:.8rem;color:#94a3b8;border-top:1px solid #e2e8f0;padding-top:16px}' >> $(OUTPUT_DIR)/static/index.html
	@echo '</style></head><body>' >> $(OUTPUT_DIR)/static/index.html
	@echo '<h1>2026 NBA Finals · Knicks vs Spurs</h1>' >> $(OUTPUT_DIR)/static/index.html
	@echo '<p>ggsql + dbt · Posit Hackathon 2026 · static chart bundle</p>' >> $(OUTPUT_DIR)/static/index.html
	@echo '<ul>' >> $(OUTPUT_DIR)/static/index.html
	@for f in $(OUTPUT_DIR)/static/*.html; do \
		name=$$(basename $$f .html); \
		label=$$(echo $$name | tr '_' ' ' | sed 's/\b./\u&/g'); \
		[ "$$name" = "index" ] && continue; \
		echo "  <li><a href=\"$$(basename $$f)\">$$label</a></li>" >> $(OUTPUT_DIR)/static/index.html; \
	done
	@echo '</ul>' >> $(OUTPUT_DIR)/static/index.html
	@echo '<footer>Stack: dbt-duckdb · ggsql · Posit Connect</footer>' >> $(OUTPUT_DIR)/static/index.html
	@echo '</body></html>' >> $(OUTPUT_DIR)/static/index.html
	@echo "✓  Static bundle → $(OUTPUT_DIR)/static/index.html"

# ── Helpers ───────────────────────────────────────────────────────────────────
_check-ggsql:
	@which $(GGSQL) > /dev/null 2>&1 || \
		(echo "✗  ggsql CLI not found. Run: make install-cli" && exit 1)

install-cli:
	@echo "▶  Installing ggsql CLI via cargo..."
	cargo install ggsql-cli
	@echo "✓  ggsql installed — run 'ggsql --version' to confirm"

clean:
	rm -rf $(OUTPUT_DIR)

help:
	@echo ""
	@echo "  make                  build dbt + render Quarto report (Option A)"
	@echo "  OUTPUT=cli   make     build dbt + render individual charts (Option B)"
	@echo "  OUTPUT=static make    build dbt + generate static HTML bundle (Option C)"
	@echo "  make build            dbt pipeline only"
	@echo "  make install-cli      install ggsql CLI via cargo"
	@echo "  make clean            remove output/ directory"
	@echo ""
