.PHONY: deploy_hugo
deploy_hugo:
	hugo
	cd public/; \
	git commit -am "Update files"; \
	git push
