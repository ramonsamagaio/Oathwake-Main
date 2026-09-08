## DCC preparation: matte removal, native-grid reduction, locked palette,
## exact atlas packing and root/crown split. Final PNG/PXO export is Pixelorama.
extends SceneTree

const DOC := "res://docs/resources/"
const PALETTE_HEX := ["293730","30312b","34363a","354741","38483b","414c38","464236","465742","494b49","506453","526047","555e45","576448","5b503d","606159","64704e","667050","6d7651","746248","76805a","77856a","79796a","7a805a","81855b","899065","8a7853","8a8e66","919080","9b9e74","a39065","a5a18c","b9a372","c4ae7d","d0c6a0","534a59","6d5d74","8b7b92","aa929a","744b3d","9b6250","b48255"]
var palette: Array[Color] = []
var cache: Dictionary = {}
var tree_sources: Array[Image] = []
var prop_sources: Array[Image] = []
var records: Array = []

func _initialize() -> void:
	for h in PALETTE_HEX: palette.append(Color.html(h))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DOC+"normalized"))
	var jobs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DOC+"normalization-jobs.json"))
	var flora:=Image.load_from_file(DOC+"generated/flora.png")
	var plants:=Image.create(192,64,false,Image.FORMAT_RGBA8)
	# Unequal generated gutters were measured, not assumed to form an exact grid.
	var flora_x := [[0,425,770,1110,1430,1790,2172],[0,420,735,1130,1410,1770,2172]]
	for i in range(12):
		var row:=i/6;var col:=i%6
		var src:=cutout(flora,Rect2i(flora_x[row][col],row*362,flora_x[row][col+1]-flora_x[row][col],362))
		var sizes:=[Vector2i(25,23),Vector2i(25,22),Vector2i(20,22),Vector2i(19,15),Vector2i(23,25),Vector2i(22,22),Vector2i(22,24),Vector2i(18,23),Vector2i(25,16),Vector2i(18,22),Vector2i(24,22),Vector2i(22,21)]
		var reduced:=fit(src,sizes[i],false)
		plants.blit_rect(reduced,Rect2i(Vector2i.ZERO,reduced.get_size()),Vector2i(col*32+(32-reduced.get_width())/2,row*32+28-reduced.get_height()))
	write_sheet("flora_ground_plants",plants)
	var trees:=Image.load_from_file(DOC+"generated/trees.png")
	var xs := [[0,342,562,865,1114,1270,1536],[0,218,422,642,967,1216,1536]]
	for i in range(12):
		var row:=i/6;var col:=i%6
		tree_sources.append(isolate_tree(cutout(trees,Rect2i(xs[row][col],row*512,xs[row][col+1]-xs[row][col],512))))
	var props:=Image.load_from_file(DOC+"generated/resources.png")
	for i in range(24): prop_sources.append(cutout(props,Rect2i((i%6)*256,(i/6)*256,256,256)))
	var crowns:=Image.create(1024,672,false,Image.FORMAT_RGBA8)
	var trunks:=Image.create(1024,192,false,Image.FORMAT_RGBA8)
	var assembled:=Image.create(1024,672,false,Image.FORMAT_RGBA8)
	for job in jobs.trees:
		var i:int=job.index
		var full:=fit(tree_sources[job.seed],Vector2i(job.max_size[0],job.max_size[1]),job.mirror)
		# Place the actual root centre on the collision anchor, rather than bbox centre.
		var base_x:=root_center(full)
		var local_full:=Image.create(128,112,false,Image.FORMAT_RGBA8)
		local_full.blit_rect(full,Rect2i(Vector2i.ZERO,full.get_size()),Vector2i(64-base_x,112-full.get_height()))
		var origin:=Vector2i((i%8)*128,(i/8)*112)
		assembled.blit_rect(local_full,Rect2i(0,0,128,112),origin)
		# Moving upper tree ends at world y=-9. Static base begins at -10:
		# two rows of identical overlap, no exposed seam or floating root.
		crowns.blit_rect(local_full,Rect2i(0,0,128,104),origin+Vector2i(0,8))
		var base:=Image.create(64,32,false,Image.FORMAT_RGBA8)
		base.blit_rect(local_full,Rect2i(32,102,64,10),Vector2i(0,22))
		var frame:=i*2
		trunks.blit_rect(base,Rect2i(0,0,64,32),Vector2i((frame%16)*64,(frame/16)*32))
		var cut:=make_stump(base)
		frame+=1
		trunks.blit_rect(cut,Rect2i(0,0,64,32),Vector2i((frame%16)*64,(frame/16)*32))
	write_sheet("tree_crowns",crowns)
	write_sheet("tree_trunks",trunks)
	assembled.save_png(DOC+"trees-assembled-native.png")
	for name in jobs.sheets:
		var sheet:Dictionary=jobs.sheets[name]
		# Keep unreferenced legacy slots available, using the same palette.
		var output:=Image.load_from_file(sheet.source)
		output.convert(Image.FORMAT_RGBA8)
		quantize(output)
		for cell in sheet.cells:
			var r:=Rect2i(cell.rect[0],cell.rect[1],cell.rect[2],cell.rect[3])
			output.fill_rect(r,Color(0,0,0,0))
			var reduced:=fit(prop_sources[cell.seed],Vector2i(cell.max_size[0],cell.max_size[1]),cell.mirror)
			output.blit_rect(reduced,Rect2i(Vector2i.ZERO,reduced.get_size()),r.position+Vector2i((r.size.x-reduced.get_width())/2,cell.baseline-reduced.get_height()))
		write_sheet(name.get_basename(),output)
	var file:=FileAccess.open(DOC+"normalized-manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"sheets":records,"palette":PALETTE_HEX},"\t"));file.close()
	print("OATHWAKE_NORMALIZE_OK sheets=",records.size()," trees=",jobs.trees.size())
	quit()

func cutout(source:Image,rect:Rect2i)->Image:
	var im:=source.get_region(rect)
	im.convert(Image.FORMAT_RGBA8)
	for y in range(im.get_height()):
		for x in range(im.get_width()):
			var c:=im.get_pixel(x,y)
			# Generated inputs are RGB with a white/checker matte. No actual alpha
			# was returned. The artwork's brightest palette entry is below 0.82.
			if minf(c.r,minf(c.g,c.b))>0.78 and maxf(c.r,maxf(c.g,c.b))-minf(c.r,minf(c.g,c.b))<0.12:
				im.set_pixel(x,y,Color(0,0,0,0))
	return im.get_region(im.get_used_rect())

func fit(source:Image,max_size:Vector2i,mirror:bool)->Image:
	var im:=source.duplicate() as Image
	var factor:=minf(float(max_size.x)/im.get_width(),float(max_size.y)/im.get_height())
	im.resize(maxi(1,roundi(im.get_width()*factor)),maxi(1,roundi(im.get_height()*factor)),Image.INTERPOLATE_NEAREST)
	if mirror:im.flip_x()
	quantize(im)
	return im

func quantize(im:Image)->void:
	for y in range(im.get_height()):
		for x in range(im.get_width()):
			var c:=im.get_pixel(x,y)
			if c.a<0.5:
				im.set_pixel(x,y,Color(0,0,0,0));continue
			var key:=c.to_html(false)
			if not cache.has(key):
				var best:=palette[0];var distance:=INF
				for p in palette:
					var d:=(c.r-p.r)*(c.r-p.r)*0.30+(c.g-p.g)*(c.g-p.g)*0.59+(c.b-p.b)*(c.b-p.b)*0.11
					if d<distance:distance=d;best=p
				cache[key]=best
			im.set_pixel(x,y,cache[key])

func root_center(im:Image)->int:
	var sum_x:=0.0;var count:=0
	for y in range(maxi(0,im.get_height()-4),im.get_height()):
		for x in range(im.get_width()):
			if im.get_pixel(x,y).a>0.5:sum_x+=x;count+=1
	return roundi(sum_x/maxi(1,count))

func make_stump(base:Image)->Image:
	var im:=base.duplicate() as Image
	var left:=im.get_width()-1;var right:=0
	for y in range(22,25):
		for x in range(im.get_width()):
			if im.get_pixel(x,y).a>0.5:left=mini(left,x);right=maxi(right,x)
	if right<left:return im
	var cx:=float(left+right)/2.0;var rx:=clampf(float(right-left)*.30,2.0,6.0)
	# The cut face belongs to the central stem, not the full spread of the roots.
	for y in range(21,29):
		for x in range(maxi(0,ceili(cx-rx)),mini(im.get_width(),floori(cx+rx)+1)):
			var shade:="5b503d" if x>cx else "746248"
			if (x+1)%4==0:shade="464236"
			im.set_pixel(x,y,Color.html(shade))
	for y in range(19,25):
		for x in range(maxi(0,left-1),mini(im.get_width(),right+2)):
			var dx:=(x-cx)/rx;var dy:=(y-21.0)/2.0
			var radial:=dx*dx+dy*dy
			if radial<=1.0:
				var color:=Color.html("746248") if radial>.68 else Color.html("b9a372")
				if radial<.23:color=Color.html("8a7853")
				im.set_pixel(x,y,color)
	return im

func isolate_tree(im:Image)->Image:
	# Unequal generated gutters let a few pixels from a neighbouring tree enter
	# the pine crop. Retain the connected tree before native reduction.
	var w:=im.get_width();var h:=im.get_height()
	var labels:=PackedInt32Array();labels.resize(w*h)
	var label:=0;var largest:=0;var largest_size:=0
	for start in range(w*h):
		if labels[start]!=0 or im.get_pixel(start%w,start/w).a<.5:continue
		label+=1
		var queue:=PackedInt32Array([start]);var head:=0
		labels[start]=label
		while head<queue.size():
			var pos:=queue[head];head+=1
			for dy in range(-1,2):
				for dx in range(-1,2):
					var x:=pos%w+dx;var y:=pos/w+dy
					if x<0 or y<0 or x>=w or y>=h:continue
					var index:=y*w+x
					if labels[index]!=0 or im.get_pixel(x,y).a<.5:continue
					labels[index]=label;queue.append(index)
		if queue.size()>largest_size:largest=label;largest_size=queue.size()
	for pos in range(w*h):
		if labels[pos]!=largest:im.set_pixel(pos%w,pos/w,Color(0,0,0,0))
	return im.get_region(im.get_used_rect())

func write_sheet(name:String,im:Image)->void:
	var path:=DOC+"normalized/"+name+".png"
	assert(im.save_png(path)==OK)
	records.append({"name":name,"path":path,"width":im.get_width(),"height":im.get_height()})
