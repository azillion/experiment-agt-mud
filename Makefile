.PHONY: build clean run test deps fix-openblas setup map map-fast export-web web-install web-dev web-build

OPENBLAS_PC := /opt/homebrew/opt/openblas/lib/pkgconfig/openblas.pc

build:
	dune build

run:
	dune exec bin/main.exe

test:
	dune runtest

clean:
	dune clean

# Install opam dependencies
deps:
	opam install owl dune ocamlfind --yes

# Patch openblas pkg-config for Apple clang OpenMP compatibility
fix-openblas:
	@if [ -f "$(OPENBLAS_PC)" ]; then \
		sed -i '' 's/omp_opt=-fopenmp$$/omp_opt=-Xpreprocessor -fopenmp/' "$(OPENBLAS_PC)"; \
		grep -q '\-lomp' "$(OPENBLAS_PC)" || \
			sed -i '' 's|^Libs: \(.*\)|Libs: \1 -L/opt/homebrew/opt/libomp/lib -lomp|' "$(OPENBLAS_PC)"; \
		echo "openblas.pc patched for Apple clang OpenMP"; \
	else \
		echo "openblas.pc not found — install openblas first: brew install openblas libomp"; \
	fi

# Full setup: fix openblas, install deps, build
setup: fix-openblas deps build

# Render world map from Graphviz dot file (respects pos= hints; slow on 10k+ nodes)
map:
	neato -Tsvg world_map.dot -o world_map.svg

# Fast renderer for huge worlds (scalable force-directed; ignores pos=)
map-fast:
	sfdp -Tsvg -Goverlap=prism world_map.dot -o world_map.svg

# Generate web/public/world.json for the 3D viewer
export-web: build
	mkdir -p web/public
	dune exec bin/main.exe < /dev/null

# Web viewer helpers
web-install:
	cd web && npm install

web-dev:
	cd web && npm run dev

web-build:
	cd web && npm run build
