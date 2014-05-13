TEX=xelatex
BIBER?=biber

dename.pdf: layout.tex content.tex build/layout.bbl
	mkdir -p ./build/msc
	$(TEX) --shell-escape -output-directory=build layout.tex
	cp build/layout.pdf dename.pdf

build/layout.bbl: citations.bib layout.tex content.tex
	mkdir -p ./build/msc
	$(TEX) --shell-escape -output-directory=build layout.tex
	$(BIBER) build/layout.bcf

content.tex: dename.md
	pandoc --smart -t latex --biblatex dename.md -o content.tex

clean:
	rm -rf dename.pdf content.tex build
