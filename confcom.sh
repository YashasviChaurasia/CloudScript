#!/bin/bash
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.0/install.sh | bash
. ~/.nvm/nvm.sh
echo "mf2">test3.log
nvm install 15.0.0
git clone https://github.com/YashasviChaurasia/Flexnet.git
cd Flexnet
npm install>test4.log
node index.js>test5.log
echo "Success"
exit
