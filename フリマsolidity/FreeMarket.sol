pragma solidity ^0.5.16;

contract FreeMarket {

    address owner; //コントラクトオーナーのアドレス
    address feeAddress; //手数料振り込み用の自分のアドレス
    uint public numItems; //商品数
    bool public stopped; //trueの場合、サーキットブレーカー(強制的な取引停止)が発動。全てのコントラクトが使用停止


    //コンストラクタ
    constructor() public {
        owner = msg.sender;
        feeAddress = ""; //手数料振り込み用の自分のアドレス
    }

    //コントラクトの呼び出しがコントラクトのオーナーか確認
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    //サーキットブレーカー
    modifier isStopped {
        require(!stopped); //stoppedがfalseであるかの確認
        _;
    }

    //サーキットブレーカーの発動・停止関数
    function toggleCircuit(bool _stopped) public onlyOwner {
        stopped = _stopped;
    }

    //コントラクトを呼び出しユーザーがアカウント登録済みか確認
    modifier onlyUser {
        require(accounts[msg.sender].registered);
        _;
    }


    //商品情報
    struct item {
        address sellerAddr; //出品者のethアドレス
        address buyerAddr; //購入者のethアドレス
        string seller; //出品者名
        string name; //商品名
        string description; //商品説明
        uint price; //価格
        bool payment; //false: 未支払い, true: 支払い済み
        bool shipment; //false: 未発送, true: 発送済み
        bool receivement; //false: 未受け取り, true: 受取済み
        bool sellerReputate; //出品者の評価完了フラグ, false: 未評価, true: 評価済み
        bool buyerReputate; //購入者の評価完了フラグ, false: 未評価, true: 評価済み
        bool stopSell; //false: 出品中, true: 出品取り消し
    }

    mapping(uint => item) public items;

    //商品画像の在り処
    //商品画像はgoogleドライブかIPFSに保存する
    struct image {
        string googleDocID; //ファイルのID
        string ipfsHash; //ファイルのハッシュ
    }

    mapping(uint => image) public images;


    //アカウント情報
    struct account {
        string name;
        string email;
        uint numTransaction; //取引回数
        int reputations; //取引評価, 大きい値ほど優良ユーザー
        bool registered; //false: アカウント未登録, true: 登録済み
        int numSell; //出品した商品の数
        int numBuy; //購入した商品の数  
    }

    mapping(address => account) public accounts; 

    //各ユーザーが出品した商品の番号を記録する配列
    mapping(address => uint[]) public sellItems; 

    //各ユーザーが購入した商品の番号を記録する配列
    mapping(address => uint[]) public buyItems; 

    //返金する際に参照するフラグ
    mapping(uint => bool) public refundFlags; //返金するとfalseからtrueに変わる。uintはnumItemsを表す

    //アカウント情報を登録する関数
    function registerAccount(string _name, string _email) public isStopped {
        require(!accounts[msg.sender].registered); //未登録のethアドレスか確認

        accounts[msg.sender].name = _name; //名前
        accounts[msg.sender].email = _email; //Eメール
        accounts[msg.sender].registered = true; //登録完了
    }

    //アカウント情報を修正する関数
    function modifyAccount(string _name, string _email) public onlyUser isStopped {
        accounts[msg.sender].name = _name;
        accounts[msg.sender].email = _email;
    }
  
    //出品する関数
    function sell(string _name, string _description, uint _price, string _googleDocID, string _ipfsHash) public onlyUser isStopped {
        items[numItems].sellerAddr = msg.sender; //出品者のethアドレス
        items[numItems].seller = accounts[msg.sender].name; //出品者名
        items[numItems].name = _name;　//商品名
        items[numItems].description = _description;　//商品説明
        items[numItems].price = _price;　//価格
        images[numItems].googleDocID = _googleDocID;　//ファイルのid
        images[numItems].ipfsHash = _ipfsHash;　//ファイルのハッシュ
        accounts[msg.sender].numSell++; //出品した商品数の更新
        sellItems[msg.sender].push(numItems); //各ユーザーが購入した商品の番号を記録
        numItems++; //商品数を加算
    }

    //出品内容を変更する関数
    function modifyItem(uint _numItems, string _name, string _description, uint _price, string _googleDocID, string _ipfsHash) public onlyUser isStopped {
        require(items[_numItems].sellerAddr == msg.sender); //コントラクトの呼び出しがmsg.senderか確認
        require(!items[_numItems].payment); //購入されていない商品か確認
        require(!items[_numItems].stopSell); //出品中の商品であるか確認

        items[_numItems].seller == accounts[msg.sender].name; //出品者名
        items[_numItems].name = _name; //商品名
        items[_numItems].description = _description;　//商品説明
        items[_numItems].price = _price;　//価格
        images[numItems].googleDocID = _googleDocID;　//ファイルのid
        images[numItems].ipfsHash = _ipfsHash;　//ファイルのハッシュ
    }

    //購入する関数
    function buy(uint _numItems) public payable onlyUser isStopped {
        require(_numItems < numItems); //存在する商品か確認
        require(!items[_numItems].payment); //商品売り切れていないか確認
        require(!items[_numItems].stopSell); //出品が取り消しになっていないか確認
        require(items[_numItems].price == msg.value); //入金金額が商品価格と一致しているか確認

        items[_numItems].buyerAddr = msg.sender; //購入者のethアドレス
        items[_numItems].payment = true; //支払済み
        items[_numItems].stopSell = true; //出品ストップ
        accounts[msg.sender].numBuy++; //購入した商品数の更新
        buyItems[msg.sender].push(_numItems); //各ユーザーが購入した商品番号の記録
    }

    //発送完了時に呼び出される関数
    function ship(uint _numItems) public onlyUser isStopped {
        require(items[_numItems].buyerAddr == msg.sender); //コントラクトの呼び出しが購入者か確認
        require(_numItems < numItems); //存在する商品か確認
        require(items[_numItems].payment); //入金済みか確認
        require(!items[_numItems].shipment); //未発送の商品か確認

        items[_numItems].shipment = true; //発送済みにする
    }

    //商品の受け取り時に呼び出される関数
    function receive(uint _numItems) public payable onlyUser isStopped {
        require(items[_numItems].buyerAddr == msg.sender); //コントラクトの呼び出しが購入者か確認
        require(_numItems < numItems); //存在する商品か確認
        require(items[_numItems].shipment); //発送済みの商品か確認
        require(!items[_numItems].receivement); //受け取り前の商品か確認

        items[_numItems].receivement = true; //受け取り
        //受け取りが完了したら出品者と自分にethを送金する
        feeAddress.transfer(items[_numItems].price * 1 / 20); //売上の5%を自分のアドレスに送金
        items[_numItems].sellerAddr.transfer(items[_numItems].price * 19 / 20); //残りを出品者に送金
    }

    //購入者が出品者を評価する関数
    function sellerEvaluate(uint _numItems, int _reputate) public onlyUser isStopped {
        require(items[_numItems].buyerAddr == msg.sender); //コントラクトの呼び出しが購入者か確認
        require(_numItems < numItems); //存在する商品か確認
        require(_reputate >= -2 && _reputate <= 2); //評価は-2から2の間で行う
        require(!items[_numItems].sellerReputate); //購入者の評価が完了していないことを確認

        accounts[items[_numItems].sellerAddr].numTransaction++; //出品者の取引回数の加算
        accounts[items[_numItems].sellerAddr].reputations += _reputate; //出品者の評価の更新
        items[_numItems].sellerReputate = true; //評価済みにする
    } 

    //出品者が購入者を評価する関数
    function buyerEvaluate(uint _numItems, int _reputate) public onlyUser isStopped {
        require(items[_numItems].sellerAddr == msg.sender); //コントラクトの呼び出しが出品者か確認
        require(_numItems < numItems); //存在する商品か確認
        require(_reputate >= -2 && _reputate <= 2); //評価は-2から2の間で行う
        require(!items[_numItems].buyerReputate); //購入者の評価が完了していないか確認

        accounts[items[_numItems].buyerAddr].numTransaction++; //購入者の取引回数の加算
        accounts[items[_numItems].buyerAddr].reputations += _reputate; //購入者の評価の更新
        items[_numItems].buyerReputate = true; //評価済みにする
    }

    //出品を取り消す関数(オーナー)
    function ownerStop(uint _numItems) public onlyOwner isStopped {
        require(items[_numItems].sellerAddr == msg.sender); //コントラクトの呼び出しが出品者か確認
        require(_numItems < numItems); //存在する商品か確認
        require(!items[_numItems].stopSell); //出品中の商品か確認
        require(!items[_numItems].payment); //購入されていない商品か確認

        items[_numItems].stopSell = true; //出品取り消し
    }

    //購入者へ返金する関数
    //商品が届かなかった時に使用する
    function ownerRefund(uint _numItems) public payable onlyOwner isStopped {
        require(_numItems < numItems); //存在する商品か確認
        require(items[_numItems].payment); //入金済み商品か確認
        require(!items[_numItems].receivement); //出品者が代金を受け取る前か確認
        require(!refundFlags[_numItems]); //既に返金されていないか確認

        items[_numItems].buyerAddr.transfer(items[_numItems].price); // 購入者へ返金
        refundFlags[_numItems] = true; //返金済みにする
    }

    //コントラクトを破棄して残金をオーナーに送る関数
    //クラッキング対策
    function kill() public onlyOwner {
        selfdestruct(owner);
    }
}












































