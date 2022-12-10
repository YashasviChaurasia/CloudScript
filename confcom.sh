#!/bin/bash
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.0/install.sh | bash
. ~/.nvm/nvm.sh
nvm install 15.0.0
git clone https://github.com/YashasviChaurasia/Flexnet.git
cd Flexnet
npm install
node index.js
echo "Success"
exit
