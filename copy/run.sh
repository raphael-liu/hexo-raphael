git rm -rf ./
cd ../hexo-raphael
hexo clean
hexo g
hexo d
cp -rf static/ ../raphael-liu.github.io/static/
cp -rf public/* ../raphael-liu.github.io/
cp -rf copy/ ../raphael-liu.github.io/
cd ../raphael-liu.github.io
chmod +x run.sh