all: coverage

coverage:
	rcov -T --exclude=.*lib.*, *_spec.rb
	@echo "Created directory 'coverage'"

clean:
	rm -rf coverage
