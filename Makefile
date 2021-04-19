MARKDOWN_FILES = $(wildcard ./specs/*.md)

.PHONY: check_toc

check_toc: $(MARKDOWN_FILES:=.toc)

%.toc:
	cp $* $*.tmp && \
	doctoc $* && \
	diff -q $* $*.tmp && \
	rm $*.tmp
