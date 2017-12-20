#/bin/bash -e

CD="$( cd "$( dirname $0 )" && pwd )"
cd $CD

if [ ! -d $CD/scriptlib ]; then
	git clone https://github.com/Oryon/scriptlib.git $CD/scriptlib
else
	echo "scriptlib repository exists"	
fi

