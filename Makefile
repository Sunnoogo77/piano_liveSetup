# Raccourcis. Tout passe par les scripts, qui restent utilisables seuls.
.PHONY: all install light build test test-audio portable calibrate preview run clean uninstall

all: install

install:            ## Installation complète (banques comprises)
	./install.sh

light:              ## Installation allégée, sans les grands pianos
	./install.sh --light

build:              ## Compiler seulement
	./scripts/build.sh

test:               ## Tests sans matériel (accords, formats)
	./scripts/test.sh

test-audio:         ## Tous les tests, dont ceux qui jouent du son
	./scripts/test.sh --audio

portable:           ## Vérifier que le cœur compile sans framework Apple
	@swiftc -swift-version 5 -typecheck -DPLS_PORTABLE \
	  Sources/Core/Model.swift Sources/Core/DSP.swift \
	  Sources/Core/Chords.swift Sources/Core/Recording.swift \
	  && echo "Le cœur est portable."

calibrate:          ## Recalculer l'équilibre des sons
	./scripts/calibrate.sh

preview:            ## Rendre l'interface en PNG dans build/ui
	@mkdir -p build/ui && ./build/bin/preview build/ui

run:                ## Lancer l'app construite
	open "build/Piano Live Setup.app"

clean:              ## Effacer build/
	rm -rf build

uninstall:          ## Retirer l'application
	./scripts/uninstall.sh

help:
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2}'
