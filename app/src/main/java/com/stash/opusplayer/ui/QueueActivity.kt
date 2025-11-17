package com.stash.opusplayer.ui

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.DividerItemDecoration
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.R
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class QueueActivity : AppCompatActivity() {

    private lateinit var recycler: RecyclerView
    private lateinit var titleText: TextView
    private var adapter = QueueAdapter { index ->
        try {
            val mgr = ((application as? com.stash.opusplayer.RevolutionaryApplication) ?: (application as com.stash.opusplayer.RevolutionaryApplication)).playerManager
            mgr.playFromPlaylist(index)
            finish()
        } catch (_: Exception) {}
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_queue)

        findViewById<View>(R.id.backButton).setOnClickListener { finish() }
        titleText = findViewById(R.id.titleText)
        recycler = findViewById(R.id.queueRecycler)
        recycler.layoutManager = LinearLayoutManager(this)
        recycler.adapter = adapter
        recycler.addItemDecoration(DividerItemDecoration(this, DividerItemDecoration.VERTICAL))

        // Enable drag-and-drop reordering and swipe-to-remove
        val touchHelper = androidx.recyclerview.widget.ItemTouchHelper(object : androidx.recyclerview.widget.ItemTouchHelper.SimpleCallback(
            androidx.recyclerview.widget.ItemTouchHelper.UP or androidx.recyclerview.widget.ItemTouchHelper.DOWN,
            androidx.recyclerview.widget.ItemTouchHelper.START or androidx.recyclerview.widget.ItemTouchHelper.END
        ) {
            override fun onMove(rv: RecyclerView, vh: RecyclerView.ViewHolder, target: RecyclerView.ViewHolder): Boolean {
                val from = vh.bindingAdapterPosition
                val to = target.bindingAdapterPosition
                adapter.onItemMoved(from, to)
                val mgr = ((application as? com.stash.opusplayer.RevolutionaryApplication) ?: (application as com.stash.opusplayer.RevolutionaryApplication)).playerManager
                mgr.moveItem(from, to)
                return true
            }
            override fun onSwiped(vh: RecyclerView.ViewHolder, dir: Int) {
                val pos = vh.bindingAdapterPosition
                val mgr = ((application as? com.stash.opusplayer.RevolutionaryApplication) ?: (application as com.stash.opusplayer.RevolutionaryApplication)).playerManager
                mgr.removeItem(pos)
            }
            override fun isLongPressDragEnabled(): Boolean = true
        })
        touchHelper.attachToRecyclerView(recycler)

        val mgr = ((application as? com.stash.opusplayer.RevolutionaryApplication) ?: (application as com.stash.opusplayer.RevolutionaryApplication)).playerManager
        lifecycleScope.launch {
            mgr.playlist.collectLatest { list ->
                adapter.submit(list, mgr.currentIndex.value)
                titleText.text = "Queue (${list.size})"
            }
        }
        lifecycleScope.launch {
            mgr.currentIndex.collectLatest { idx ->
                adapter.updateCurrent(idx)
            }
        }
    }

    private class QueueAdapter(
        val onClick: (Int) -> Unit
    ) : RecyclerView.Adapter<QueueViewHolder>() {
        private var items: List<com.stash.opusplayer.data.Song> = emptyList()
        private var currentIndex: Int = -1

        fun submit(list: List<com.stash.opusplayer.data.Song>, current: Int) {
            items = list
            currentIndex = current
            notifyDataSetChanged()
        }
        fun updateCurrent(current: Int) {
            currentIndex = current
            notifyDataSetChanged()
        }
        fun onItemMoved(from: Int, to: Int) {
            if (from !in items.indices || to !in items.indices) return
            val mutable = items.toMutableList()
            val item = mutable.removeAt(from)
            mutable.add(to, item)
            items = mutable
            notifyItemMoved(from, to)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): QueueViewHolder {
            val v = layoutInflater(parent).inflate(android.R.layout.simple_list_item_2, parent, false)
            return QueueViewHolder(v, onClick)
        }
        override fun getItemCount(): Int = items.size
        override fun onBindViewHolder(holder: QueueViewHolder, position: Int) {
            val s = items[position]
            holder.bind(s.displayName, s.artistName, position == currentIndex, position)
        }
        private fun layoutInflater(parent: ViewGroup) = android.view.LayoutInflater.from(parent.context)
    }

    private class QueueViewHolder(itemView: View, val onClick: (Int) -> Unit) : RecyclerView.ViewHolder(itemView) {
        private val title = itemView.findViewById<TextView>(android.R.id.text1)
        private val subtitle = itemView.findViewById<TextView>(android.R.id.text2)
        fun bind(t: String, sub: String, isCurrent: Boolean, position: Int) {
            title.text = if (isCurrent) "• $t" else t
            subtitle.text = sub
            itemView.setOnClickListener { onClick(position) }
        }
    }
}
