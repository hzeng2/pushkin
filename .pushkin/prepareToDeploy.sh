#!/bin/bash

set -e

bold=$(tput bold)
normal=$(tput sgr0)
echoBold () {
	echo "${bold}${1}${normal}"
}
confirmContinue () {
	read -p "${1} (y/n) " -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		exit
	fi
}
usage() {
	echo "Usage: $0 [-mcbh]"
	echo "Each options represents which phase to stop at."
	echo "m: stop after moving quiz files to their destinations in the pushkin source code"
	echo "c: stop after compiling the front end"
	echo "b: stop after building the docker images"
}

# args
do_copy_quizzes=true
do_comp_front=true
do_copy_comp_files=true
do_build_docker=true
do_build_quiz_dockers=true
do_push_docker=true
do_docker_compose=true
do_append_quiz_composes=true
do_sync_aws=true

fe_quiz_list='front-end/src/quizzes/quizzes.js'
pushkin_root=$(realpath .)

#while getopts "mcbh" o; do
#	case "${o}" in
#		m)
#			do_comp_front=false
#			do_build_docker=false
#			do_push_docker=false
#			;;
#		c)
#			do_build_docker=false
#			do_push_docker=false
#			;;
#		b)
#			do_push_docker=false
#			;;
#		h)
#			usage
#			;;
#	esac
#done
#shift $((OPTIND-1))

# setup
# note that front-end is not in here
# this is because it does not run in a container on the server;
# it's sole purpose is to create static js/html/css/etc. code
# that the server container will upload
build_images=('api' 'cron' 'db-worker' 'server')

default='.env'
read -p "environment file: (${default}): " env_file
env_file=${env_file:-${default}}

. ${env_file}
if [[ -z ${image_prefix} && ("$do_build_docker" = true || "$do_build_quiz_dockers" = true) ]]; then
	echo "${bold}Warning!${normal} image_prefix is not set in the environment file"
	echo "	This means the docker-compose file might not use the correct images generated by this script"
	confirmContinue "are you sure you wish to continue?"
fi
if [[ -z ${image_tag} && ("$do_build_docker" = true || "$do_build_quiz_dockers" = true) ]]; then
	echo "${bold}Warning!${normal} image_tag is not set in the environment file"
	echo "	This means the docker-compose file might not use the correct images generated by this script"
	confirmContinue "are you sure you wish to continue?"
fi


# projectPrefix
# repoName
# tag

if [[ "$do_build_docker" = true || "$do_build_quiz_dockers" = true ]]; then
	default=${image_prefix}
	read -p "docker repo (${default}): " docker_repo
	docker_repo=${docker_repo:-${default}}

	default="${image_tag}"
	read -p "tag to give new images on upload (${default}): " docker_label
	docker_label=${docker_label:-${default}}
fi

if [[ "$do_docker_compose" = true || "$do_append_quiz_composes" = true ]]; then
	default='docker-compose.production.yml'
	read -p "docker compose file (${default}): " docker_compose
	docker_compose=${docker_compose:-${default}}

	default="$(basename -s '.yml' ${docker_compose}).noEnvDependency.yml"
	read -p "new compose file with substituted env variables (${default}): " docker_compose_new
	docker_compose_new=${docker_compose_new:-${default}}
fi

if [[ "$do_comp_front" = true ]]; then
	default='front-end/dist'
	read -p "dist web folder compiled location (${default}): " pub_web_src
	pub_web_src=${pub_web_src:-${default}}
fi

if [[ "$do_copy_comp_files" = true ]]; then
	default='server/html'
	read -p "public web folder destination (${default}): " pub_web_dst
	pub_web_dst=${pub_web_dst:-${default}}
fi

# explain
echoBold "will build images from:"
for i in "${build_images[@]}"; do
	echo "	${i}"
done
echoBold "will compile front-end (run 'node compile.js') from ${normal}front-end${bold} folder"
echoBold "will copy compiled web code from ${normal}${pub_web_src} ${bold}to${normal} ${pub_web_dst}"
echoBold "will DELETE everything in api/controllers, db-worker/models, db-worker/migrations db-worker/seeds, front-end/src/quizzes, server/html, directories in cron/scripts"
echoBold "will sync front-end/dist with ${s3_bucket_name} s3 bucket"

echo
confirmContinue "continue ?"


######################## start ########################
# clean
echoBold "cleaning"
rm -rf ./api/controllers/*
rm -rf ./db-worker/models/*
rm -rf ./db-worker/migrations/*
rm -rf ./db-worker/seeds/*
rm -rf ./front-end/src/quizzes/*/
rm -rf ./cron/scripts/*/
rm -rf ./server/html/*


# move user specific quizzes to appropriate locations
if [[ "$do_copy_quizzes" = true ]]; then
	echoBold "moving back new quizzes from quizzes to appropriate locations and writing quiz list to front-end"

	# might not have all things for cp
	set +e

	for qPath in "${pushkin_root}/quizzes/quizzes/"*; do
		qName=$(basename ${qPath})

		#echo cp -r "${qPath}/api_controllers/"* "${pushkin_root}/api/controllers/"
		mkdir "${pushkin_root}/api/controllers/${qName}"
		cp -r "${qPath}/api_controllers/"* "${pushkin_root}/api/controllers/${qName}"
		#echo 
		#echo 

		mkdir "${pushkin_root}/cron/scripts/${qName}"
		#echo cp -r "${qPath}/cron_scripts/scripts/"*/* "${pushkin_root}/cron/scripts/${qName}"
		cp -r "${qPath}/cron_scripts/scripts/"*/* "${pushkin_root}/cron/scripts/${qName}"
		#echo 
		#echo 
		cat "${qPath}/cron_scripts/crontab.txt" >> "${pushkin_root}/cron/crontab"

		mkdir "${pushkin_root}/db-worker/models/${qName}"
		#echo cp "${qPath}/db_models/"* "${pushkin_root}/db-worker/models/${qName}"
		cp "${qPath}/db_models/"* "${pushkin_root}/db-worker/models/${qName}"
		#echo 
		#echo 

		# mkdir "${pushkin_root}/db-worker/migrations/${qName}"
		#echo cp -r "${qPath}/db_migrations/"* "${pushkin_root}/db-worker/migrations/"
		cp -r "${qPath}/db_migrations/"* "${pushkin_root}/db-worker/migrations/"
		#echo 
		#echo 

		mkdir "${pushkin_root}/db-worker/seeds/${qName}"
		#echo cp -r "${qPath}/db_seeds/"* "${pushkin_root}/db-worker/seeds/${qName}"
		cp -r "${qPath}/db_seeds/"* "${pushkin_root}/db-worker/seeds/${qName}"
		#echo 
		#echo 

		mkdir "${pushkin_root}/front-end/src/quizzes/${qName}"
		#echo cp -r "${qPath}/quiz_page/"* "${pushkin_root}/front-end/src/quizzes/${qName}"
		cp -r "${qPath}/quiz_page/"* "${pushkin_root}/front-end/src/quizzes/${qName}"
		#echo 

		# quizzes/quizzes/[quiz]/db-workers does not need to be moved
		# because it's just docker and not physically referenced by anything
	done

	set -e

	# build front-end/src/quizzes/quizzes.js "config"
	# to be used by quiz page
	echo '// This file generated automatically by prepareToDeploy.sh' > "${pushkin_root}/$fe_quiz_list"
	wqf () { echo ${1} >> "${pushkin_root}/${fe_quiz_list}"; }
	wqf '// Do not edit directly (your changes will be overwritten)'
	wqf ''

	for qPath in "${pushkin_root}/quizzes/quizzes/"*; do
		qName=$(basename ${qPath})
		wqf "import ${qName} from './${qName}';"
	done

	wqf 'export default {'

	for qPath in "${pushkin_root}/quizzes/quizzes/"*; do
		qName=$(basename "${qPath}")
		wqf "	${qName}: ${qName},"
	done

	wqf '};'
fi

# compile front-end
if [[ "$do_comp_front" = true ]]; then
	echoBold "compiling from front-end"
	cd front-end
	node compile.js
	#--publicPath="${cloudfront_url}"
	cd ..
fi

# copy compiled files
if [[ "$do_copy_comp_files" = true ]]; then
	echoBold "copying web files"
	cp -rf "./${pub_web_src}"/* "./${pub_web_dst}"
fi

# build pushkin docker images
if [[ "$do_build_docker" = true ]]; then
	for i in "${build_images[@]}"; do
		echoBold "building ${i}"
		docker build -t "${docker_repo}/pushkin-${i}" -t "${docker_repo}/pushkin-${i}:${docker_label}" "${i}/"
		echoBold "finished building ${i}"
	done
fi

# build quiz docker images
if [[ "$do_build_quiz_dockers" = true ]]; then
	echoBold "building quiz-specific db worker docker images"
	for qPath in "${pushkin_root}/quizzes/quizzes/"*; do
		qName=$(basename "$qPath")
		if [ -d "$qPath/db_workers" ] && [ -f "$qPath/db_workers/Dockerfile" ]; then
			echoBold "building ${normal}${qName}"
			docker build -t "${docker_repo}/pushkin-${qName}-db-worker:${docker_label}" \
				-t "${docker_repo}/pushkin-${qName}-db-worker" "$qPath"/db_workers
			build_images+=("${qName}-db-worker")
		else
			echo "did not detect a db worker for $qName, skipping"
		fi
	done
fi

# push to dockerhub
if [[ "$do_push_docker" = true ]]; then
	echoBold "pushing to dockerhub"
	for i in "${build_images[@]}"; do
		echoBold "pushing ${i}"
		docker push "${docker_repo}/pushkin-${i}"
		docker push "${docker_repo}/pushkin-${i}:${docker_label}"
		echoBold "finished pushing ${i}"
	done
fi

# append quiz-specific db-workers
if [[ "$do_append_quiz_composes" = true ]]; then
	echoBold "appending quiz composes to compose file"
 
	sed -i.sedBak '/^#@AUTOAPPENDBELOWTHISLINE$/,$d' ${docker_compose}
	echo '#@AUTOAPPENDBELOWTHISLINE' >> ${docker_compose}

	for qPath in "${pushkin_root}/quizzes/quizzes/"*; do
		qName=$(basename "$qPath")
		if [ -f "$qPath/db_workers/docker_compose_appendage.yml" ]; then
			cat "${qPath}/db_workers/docker_compose_appendage.yml" >> "${pushkin_root}/${docker_compose}"
		fi
	done
fi

# implemented in .pushkin/bin/makeNoEnvDepDockerCompose.sh
# remove .env variables > docker-compose.production.noEnvDependency.yml
#if [[ "$do_docker_compose" = true ]]; then
#	echoBold "subsituting docker compose file environment references"
#	set -a
#	. $env_file
#	set +a
#	cat $docker_compose | envsubst > $docker_compose_new
#fi

# sync front-end/dist with s3 bucket
if [[ "$do_sync_aws" = true ]]; then
	echoBold "syncing ${pub_web_dst} with ${s3_bucket_name} s3 bucket"
	aws s3 sync "./${pub_web_dst}" s3://${s3_bucket_name}
fi

# done
echoBold "preparation complete"









